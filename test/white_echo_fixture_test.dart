import 'dart:io';

import 'package:ai_tavern/services/export_service.dart';
import 'package:ai_tavern/models/play_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('White Echo 外置故事框架可以作为完整存档导入', () async {
    final source = await File(
      'examples/white_echo_story_framework.ai-tavern.json',
    ).readAsString();
    final save = ExportService().decodeImportedSave(source);

    expect(save.name, contains('White Echo'));
    expect(save.characters, hasLength(4));
    expect(save.characters.where((item) => item.enabled), hasLength(1));
    expect(save.lorebook, hasLength(13));
    expect(save.messages, isEmpty);
    expect(save.openingMessage, contains('你记得什么'));
    expect(save.roleplayRules, contains('第八章电梯身份认证后'));
    expect(save.memorySummary.content, contains('序章开场'));
    expect(save.playMode, PlayMode.choice);
    expect(save.choiceCount, 6);
    expect(save.pendingChoices, hasLength(6));
  });

  test('圣女转生事故框架包含完整角色、世界书和六选项开局', () async {
    final source = await File(
      'examples/saint_reincarnation_accident_story_framework.ai-tavern.json',
    ).readAsString();
    final save = ExportService().decodeImportedSave(source);

    expect(save.name, contains('圣女转生事故'));
    expect(save.characters, hasLength(9));
    expect(save.lorebook, hasLength(22));
    expect(save.openingMessage, contains('芙洛莉娅'));
    expect(save.roleplayRules, contains('秘密门禁'));
    expect(save.memorySummary.content, contains('第一章开场'));
    expect(save.playMode, PlayMode.choice);
    expect(save.choiceCount, 6);
    expect(save.pendingChoices, hasLength(6));
  });

  test('退役英雄也要上早八框架包含30章门禁与六选项开局', () async {
    final source = await File(
      'examples/retired_hero_early_eight_story_framework.ai-tavern.json',
    ).readAsString();
    final save = ExportService().decodeImportedSave(source);

    expect(save.name, contains('退役英雄也要上早八'));
    expect(save.characters, hasLength(11));
    expect(save.lorebook, hasLength(32));
    expect(save.openingMessage, contains('三条规矩'));
    expect(save.roleplayRules, contains('秘密与时间门禁'));
    expect(save.memorySummary.content, contains('第一章开场'));
    expect(save.playMode, PlayMode.choice);
    expect(save.choiceCount, 6);
    expect(save.pendingChoices, hasLength(6));
  });
}
