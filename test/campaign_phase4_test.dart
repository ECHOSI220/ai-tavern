import 'dart:convert';

import 'package:ai_tavern/models/campaign_models.dart';
import 'package:ai_tavern/models/character.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/repositories/campaign_repository.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:ai_tavern/services/trpg/campaign_codec_service.dart';
import 'package:ai_tavern/services/trpg/campaign_template_service.dart';
import 'package:ai_tavern/services/trpg/ai_campaign_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const codec = CampaignCodecService();

  test('campaign JSON harness extracts JSON from DeepSeek explanations', () {
    final decoded = AICampaignGenerator.decodeJsonObject(
      '我们会修复格式，下面是结果： {这不是有效的 JSON}\n```json\n'
      '{"title":"雾港疑云","nested":{"text":"括号 } 仍在字符串中"}}\n'
      '```\n以上内容不要再处理。',
    );
    expect(decoded['title'], '雾港疑云');
    expect((decoded['nested'] as Map)['text'], '括号 } 仍在字符串中');
  });

  test('legacy campaign JSON migrates to v2 and validates safely', () {
    final imported = codec.importCampaign(
      jsonEncode({
        'id': 'legacy',
        'title': '旧剧本',
        'locations': [
          {'id': 'harbor', 'name': '港口'},
        ],
        'npcs': [
          {'id': 'guard', 'name': '守卫', 'locationId': 'harbor'},
        ],
        'possibleEndings': ['离开港口'],
      }),
    );
    expect(imported.schemaVersion, campaignSchemaVersion);
    expect(imported.source, CampaignSourceType.imported);
    expect(codec.validateCampaign(imported).isValid, isTrue);
  });

  test('invalid references and duplicate ids are rejected', () {
    final now = DateTime(2026, 8, 14);
    final campaign = CampaignDocument(
      id: 'bad',
      title: '坏引用',
      createdAt: now,
      updatedAt: now,
      locations: const [CampaignLocation(id: 'same', name: 'A')],
      npcs: const [
        TRPGNPCProfile(npcId: 'same', name: 'B', locationId: 'missing'),
      ],
    );
    final result = codec.validateCampaign(campaign);
    expect(result.isValid, isFalse);
    expect(result.errors.map((value) => value.code), contains('duplicate_id'));
    expect(result.errors.map((value) => value.code), contains('npc_location'));
  });

  test('tavern character becomes independent NPC profile reference', () {
    const character = Character(
      id: 'tavern-laplace',
      name: '拉毗',
      personality: '果断但不会盲从',
      exampleDialogue: '先确认风险。',
    );
    final profile = TRPGNPCProfile.fromCharacter(
      character,
      role: CampaignNpcRole.companion,
    );
    final instance = NPCInstanceState(
      npcId: profile.npcId,
      sourceCharacterId: profile.sourceCharacterId,
      relationship: 30,
    ).copyWith(relationship: 55, inventory: const ['medkit']);
    expect(profile.sourceCharacterId, character.id);
    expect(instance.relationship, 55);
    expect(character.personality, '果断但不会盲从');
    expect(character.toJson(), isNot(containsPair('inventory', anything)));
  });

  test('mist harbor fixture meets phase 4 content minimums', () {
    final campaign = const CampaignTemplateService().mistHarbor();
    expect(campaign.npcs, hasLength(greaterThanOrEqualTo(4)));
    expect(campaign.locations, hasLength(greaterThanOrEqualTo(4)));
    expect(campaign.clues, hasLength(greaterThanOrEqualTo(8)));
    expect(campaign.quests, hasLength(greaterThanOrEqualTo(3)));
    expect(campaign.secrets, hasLength(greaterThanOrEqualTo(2)));
    expect(
      campaign.npcs.any((value) => value.role == CampaignNpcRole.companion),
      isTrue,
    );
    expect(
      campaign.clues.any(
        (value) => value.visibility == InformationVisibility.playerPrivate,
      ),
      isTrue,
    );
  });

  test('campaign repository persists v2 documents in database v7', () async {
    sqfliteFfiInit();
    final storage = StorageService();
    await storage.initialize(databasePath: inMemoryDatabasePath);
    addTearDown(storage.close);
    final repository = CampaignRepository(storage);
    final campaign = const CampaignTemplateService().mistHarbor();
    await repository.upsert(campaign);
    final restored = await repository.getById(campaign.id);
    expect(restored?.schemaVersion, campaignSchemaVersion);
    expect(restored?.clues.length, 8);
  });
}
