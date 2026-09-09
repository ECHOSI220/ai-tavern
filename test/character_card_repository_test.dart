import 'package:ai_tavern/models/character.dart';
import 'package:ai_tavern/repositories/character_card_repository.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('角色卡库独立保存、更新和删除角色卡', () async {
    sqfliteFfiInit();
    final storage = StorageService();
    await storage.initialize(databasePath: inMemoryDatabasePath);
    addTearDown(storage.close);
    final repository = CharacterCardRepository(storage);
    const source = Character(
      id: 'card-1',
      name: '莉娅',
      avatar: r'C:\images\liya.png',
      personality: '冷静',
    );

    await repository.upsert(source);
    expect((await repository.getAll()).single.avatar, contains('liya.png'));

    await repository.upsert(source.copyWith(personality: '冷静、谨慎'));
    expect((await repository.getAll()).single.personality, contains('谨慎'));

    await repository.delete(source.id);
    expect(await repository.getAll(), isEmpty);
  });
}
