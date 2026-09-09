import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/save_slot.dart';
import '../services/storage_service.dart';
import 'message_repository.dart';

class SaveRepository {
  SaveRepository(this._storage) : _messages = MessageRepository(_storage);

  final StorageService _storage;
  final MessageRepository _messages;

  Future<List<SaveSlot>> getAll() async {
    final rows = await _storage.database.query(
      'save_slots',
      columns: ['payload', 'message_count'],
      orderBy: 'last_played_at DESC',
    );
    return rows.map((row) {
      final save = _decode(row['payload']! as String);
      return save.copyWith(
        messages: const [],
        storedMessageCount: row['message_count']! as int,
      );
    }).toList();
  }

  Future<SaveSlot?> getById(String id) async {
    final rows = await _storage.database.query(
      'save_slots',
      columns: ['payload'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final decoded = _decode(rows.single['payload']! as String);
    var messages = await _messages.getForSave(id);
    // v1 存档的消息在 payload 中，首次读取时无感迁移到独立表。
    if (messages.isEmpty && decoded.messages.isNotEmpty) {
      messages = decoded.messages;
      await _messages.replaceForSave(id, messages);
    }
    return decoded.copyWith(messages: messages);
  }

  Future<void> upsert(SaveSlot save, {bool replaceMessages = false}) async {
    final hasFullMessageState = save.storedMessageCount == null;
    final previousCount = await _messages.count(save.id);
    final initialCount = hasFullMessageState
        ? (replaceMessages ? save.messages.length : previousCount)
        : save.storedMessageCount ?? previousCount;
    final payload = save.copyWith(messages: const []).toJson();
    final row = <String, Object?>{
      'id': save.id,
      'name': save.name,
      'player_name': save.playerName,
      'message_count': initialCount,
      'updated_at': save.updatedAt.millisecondsSinceEpoch,
      'last_played_at': save.lastPlayedAt.millisecondsSinceEpoch,
      'payload': jsonEncode(payload),
    };
    // Do not use INSERT OR REPLACE here. SQLite implements REPLACE as
    // DELETE + INSERT, which triggers messages.save_id ON DELETE CASCADE and
    // silently wipes the whole conversation whenever metadata is updated.
    await _storage.database.transaction((transaction) async {
      final updated = await transaction.update(
        'save_slots',
        row,
        where: 'id = ?',
        whereArgs: [save.id],
      );
      if (updated == 0) await transaction.insert('save_slots', row);
    });

    if (hasFullMessageState && replaceMessages) {
      await _messages.replaceForSave(save.id, save.messages);
    } else if (hasFullMessageState) {
      // Normal chat saving is incremental. A second app window or an older
      // screen may still hold a stale snapshot; it must never erase messages
      // written by the newer window merely by saving its metadata.
      await _messages.upsertAll(save.messages);
    }
    final actualCount = await _messages.count(save.id);
    await _storage.database.update(
      'save_slots',
      {'message_count': actualCount},
      where: 'id = ?',
      whereArgs: [save.id],
    );
  }

  Future<void> delete(String id) async {
    // messages 表通过外键 ON DELETE CASCADE 随存档删除。
    await _storage.database.delete(
      'save_slots',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<SaveSlot> duplicate(SaveSlot source) async {
    final completeSource = await getById(source.id) ?? source;
    final now = DateTime.now();
    const uuid = Uuid();
    final newSaveId = uuid.v4();
    final messageIds = {
      for (final message in completeSource.messages) message.id: uuid.v4(),
    };
    final deepCopy = SaveSlot.fromJson(completeSource.toJson());
    final copy = deepCopy.copyWith(
      id: newSaveId,
      name: '${completeSource.name} 副本',
      characters: deepCopy.characters
          .map((character) => character.copyWith(id: uuid.v4()))
          .toList(),
      lorebook: deepCopy.lorebook
          .map((entry) => entry.copyWith(id: uuid.v4()))
          .toList(),
      messages: deepCopy.messages
          .map(
            (message) => message.copyWith(
              id: messageIds[message.id],
              saveId: newSaveId,
              parentMessageId: message.parentMessageId == null
                  ? null
                  : messageIds[message.parentMessageId],
            ),
          )
          .toList(),
      memorySummary: deepCopy.memorySummary.copyWith(
        coveredMessageId: deepCopy.memorySummary.coveredMessageId == null
            ? null
            : messageIds[deepCopy.memorySummary.coveredMessageId],
      ),
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
    );
    await upsert(copy);
    return copy;
  }

  SaveSlot _decode(String payload) =>
      SaveSlot.fromJson((jsonDecode(payload) as Map).cast<String, Object?>());
}
