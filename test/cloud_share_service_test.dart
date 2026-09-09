import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tavern/models/character.dart';
import 'package:ai_tavern/models/save_slot.dart';
import 'package:ai_tavern/models/story_card.dart';
import 'package:ai_tavern/services/cloud_share_service.dart';

void main() {
  test(
    'character export uses an allowlist without secrets, relationships or local avatars',
    () {
      const c = Character(
        id: 'local-id',
        name: '测试',
        secrets: 'PRIVATE_SECRET',
        avatar: 'C:\\private.png',
        relationship: 'PRIVATE_RELATION',
        description: '公开设定',
      );
      final encoded = CloudShareService.encode(
        CloudShareService.characterPackage(c),
      );
      expect(encoded, contains('公开设定'));
      for (final value in [
        'PRIVATE_SECRET',
        'PRIVATE_RELATION',
        'private.png',
        'local-id',
      ]) {
        expect(encoded, isNot(contains(value)));
      }
    },
  );
  test('story export does not include runtime memories or credentials', () {
    final save = SaveSlot.create(name: '故事', scenario: '公开前提').copyWith(
      conversationMemory: 'PRIVATE_MEMORY',
      playerName: 'PRIVATE_PLAYER',
    );
    final card = StoryCard.fromSave(save);
    final encoded = CloudShareService.encode(
      CloudShareService.storyPackage(card),
    );
    expect(encoded, contains('公开前提'));
    expect(encoded, isNot(contains('PRIVATE_')));
    expect(jsonDecode(encoded)['contentType'], 'CAMPAIGN_TEMPLATE');
  });
  test('sensitive fields, paths and oversize are rejected', () {
    for (final data in [
      {'apiKey': 'x'},
      {
        'nested': {'privateChat': 'x'},
      },
      {'text': 'C:\\private.txt'},
      {'text': 'x' * 2000001},
    ]) {
      expect(
        () => CloudShareService.encode({
          'schemaVersion': 1,
          'contentType': 'OTHER',
          'data': data,
        }),
        throwsFormatException,
      );
    }
  });
}
