import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

import '../models/chat_message.dart';
import '../services/storage_service.dart';

class MessageRepository {
  MessageRepository(this._storage);

  final StorageService _storage;

  Future<List<ChatMessage>> getForSave(String saveId) async {
    final rows = await _storage.database.query(
      'messages',
      columns: ['payload'],
      where: 'save_id = ?',
      whereArgs: [saveId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (row) => ChatMessage.fromJson(
            (jsonDecode(row['payload']! as String) as Map)
                .cast<String, Object?>(),
          ),
        )
        .toList();
  }

  Future<int> count(String saveId) async {
    final rows = await _storage.database.rawQuery(
      'SELECT COUNT(*) AS total FROM messages WHERE save_id = ?',
      [saveId],
    );
    return (rows.single['total'] as int?) ?? 0;
  }

  Future<void> upsert(ChatMessage message) async {
    await _storage.database.insert(
      'messages',
      _row(message),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertAll(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    await _storage.database.transaction((transaction) async {
      for (final message in messages) {
        await transaction.insert(
          'messages',
          _row(message),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> replaceForSave(String saveId, List<ChatMessage> messages) async {
    await _storage.database.transaction((transaction) async {
      await transaction.delete(
        'messages',
        where: 'save_id = ?',
        whereArgs: [saveId],
      );
      for (final message in messages) {
        await transaction.insert(
          'messages',
          _row(message),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> delete(String id) async {
    await _storage.database.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Map<String, Object?> _row(ChatMessage message) => {
    'id': message.id,
    'save_id': message.saveId,
    'role': message.role.name,
    'created_at': message.createdAt.microsecondsSinceEpoch,
    'payload': jsonEncode(message.toJson()),
  };
}
