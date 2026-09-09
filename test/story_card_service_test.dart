import 'dart:io';

import 'package:ai_tavern/models/save_slot.dart';
import 'package:ai_tavern/models/story_card.dart';
import 'package:ai_tavern/services/export_service.dart';
import 'package:ai_tavern/services/official_story_card_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('White Echo 外置框架可初始化为受保护官方卡片', () async {
    final source = await File(
      'examples/white_echo_story_framework.ai-tavern.json',
    ).readAsString();
    final card = const OfficialStoryCardService().decodeWhiteEcho(source);

    expect(card.id, officialWhiteEchoCardId);
    expect(card.isOfficial, isTrue);
    expect(card.template.characters, hasLength(4));
    expect(card.template.lorebook, hasLength(13));
    expect(card.createSave().pendingChoices, hasLength(6));
  });

  test('剧情卡片 JSON 往返后作为新的自制卡片导入', () {
    final service = ExportService();
    final source = StoryCard.fromSave(SaveSlot.create(name: '雨夜车站'));
    final imported = service.decodeImportedStoryCard(
      service.encodeStoryCard(source),
    );

    expect(imported.id, isNot(source.id));
    expect(imported.name, '雨夜车站');
    expect(imported.isOfficial, isFalse);
  });

  test('完整存档 JSON 也可以直接收藏为剧情卡片', () {
    final service = ExportService();
    final imported = service.decodeImportedStoryCard(
      service.encodeSave(SaveSlot.create(name: '旧存档剧情')),
    );

    expect(imported.name, '旧存档剧情');
    expect(imported.template.messages, isEmpty);
  });

  test('圣女转生事故外置框架可初始化为带封面的官方卡片', () async {
    final source = await File(
      'examples/saint_reincarnation_accident_story_framework.ai-tavern.json',
    ).readAsString();
    final card = const OfficialStoryCardService().decodeSaintReincarnation(
      source,
      coverImage: 'stored-cover.png',
    );

    expect(card.id, officialSaintReincarnationCardId);
    expect(card.isOfficial, isTrue);
    expect(card.template.coverImage, 'stored-cover.png');
    expect(card.template.characters, hasLength(9));
    expect(card.template.lorebook, hasLength(22));
    expect(card.createSave().pendingChoices, hasLength(6));
  });

  test('退役英雄也要上早八框架可初始化为带封面的官方卡片', () async {
    final source = await File(
      'examples/retired_hero_early_eight_story_framework.ai-tavern.json',
    ).readAsString();
    final card = const OfficialStoryCardService().decodeRetiredHeroEarlyEight(
      source,
      coverImage: 'stored-retired-hero-cover.png',
    );

    expect(card.id, officialRetiredHeroEarlyEightCardId);
    expect(card.isOfficial, isTrue);
    expect(card.template.coverImage, 'stored-retired-hero-cover.png');
    expect(card.template.characters, hasLength(11));
    expect(card.template.lorebook, hasLength(32));
    expect(card.createSave().pendingChoices, hasLength(6));
  });
}
