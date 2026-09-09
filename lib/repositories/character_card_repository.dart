import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

import '../models/character.dart';
import '../services/storage_service.dart';

class CharacterCardRepository {
  const CharacterCardRepository(this._storage);

  final StorageService _storage;

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

  Future<void> upsert(Character character) async {
    await _storage.database.insert('character_cards', {
      'id': character.id,
      'name': character.name,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'payload': jsonEncode(character.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    await _storage.database.delete(
      'character_cards',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
