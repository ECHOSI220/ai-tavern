import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

import '../models/character.dart';
import 'package:uuid/uuid.dart';
import '../models/character_social.dart';
import 'character_social_repository.dart';
import '../services/character_social/social_avatar_codec.dart';
import '../services/storage_service.dart';

class CharacterCardRepository {
  const CharacterCardRepository(this._storage);

  final StorageService _storage;
  StorageService get storage => _storage;

  Future<List<Character>> getAll() async {
    final rows = await _storage.database.query(
      'character_cards',
      columns: ['payload'],
      orderBy: 'updated_at DESC',
    );
    return rows
        .map(
          (row) => Character.fromJson(
            (jsonDecode(row['payload']! as String) as Map)
                .cast<String, Object?>(),
          ),
        )
        .toList();
  }

  Future<void> upsert(Character character, {bool syncSocial = true}) async {
    await _storage.database.insert('character_cards', {
      'id': character.id,
      'name': character.name,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'payload': jsonEncode(character.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (syncSocial && await hasSocialReferences(character.id)) {
      final owners = await _storage.database.rawQuery(
        'SELECT DISTINCT owner_id FROM character_social_records WHERE kind = ? AND character_id = ? AND deleted = 0',
        ['contact', character.id],
      );
      final data = await SocialAvatarCodec.encode(character);
      for (final row in owners) {
        final repo = CharacterSocialRepository(
          _storage,
          owner: row['owner_id']! as String,
        );
        final id = const Uuid().v5(Namespace.url.value, 'card:${character.id}');
        final mirror = await repo.get(id);
        if (mirror != null &&
            mirror.conflict == null &&
            jsonEncode(mirror.data) != jsonEncode(data)) {
          await repo.save(mirror.change(data));
        }
      }
    }
  }

  Future<bool> hasSocialReferences(String id) async {
    final tables = await _storage.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='character_social_records'",
    );
    if (tables.isEmpty) return false;
    final refs = await _storage.database.query(
      'character_social_records',
      columns: ['id'],
      where: 'kind = ? AND character_id = ? AND deleted = 0',
      whereArgs: ['contact', id],
      limit: 1,
    );
    return refs.isNotEmpty;
  }

  Future<void> delete(String id, {bool preserveSocialSnapshot = false}) async {
    if (await hasSocialReferences(id)) {
      if (!preserveSocialSnapshot) {
        throw StateError('角色仍在社交系统使用，请先选择保留角色快照或取消。');
      }
      final card = (await getAll()).where((c) => c.id == id).firstOrNull;
      if (card != null) {
        final owners = await _storage.database.rawQuery(
          'SELECT DISTINCT owner_id FROM character_social_records WHERE kind = ? AND character_id = ? AND deleted = 0',
          ['contact', id],
        );
        for (final owner in owners) {
          final repo = CharacterSocialRepository(
            _storage,
            owner: owner['owner_id']! as String,
          );
          final mirrorId = const Uuid().v5(Namespace.url.value, 'card:$id');
          final mirror = await repo.get(mirrorId);
          final data = await SocialAvatarCodec.encode(card);
          await repo.save(
            mirror == null
                ? SocialRecord.create(
                    'card',
                    data,
                    id: mirrorId,
                    characterId: id,
                  )
                : mirror.change(data),
          );
        }
      }
    }
    await _storage.database.delete(
      'character_cards',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
