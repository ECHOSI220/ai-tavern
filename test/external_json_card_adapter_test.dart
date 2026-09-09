import 'dart:io';

import 'package:ai_tavern/services/export_service.dart';
import 'package:ai_tavern/services/external_json_card_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

const _sillyTavernSample =
    r'D:\xwechat_files\wxid_vmdlhgv8o9mi22_d0a7\msg\file\2026-08\无职转生 RPG + 世界书——中文版——.json';
const _nativeSample =
    r'D:\xwechat_files\wxid_vmdlhgv8o9mi22_d0a7\msg\file\2026-08\无职转生_RPG_世界书_方案A.json';
const _largeNativeSample =
    r'D:\xwechat_files\wxid_vmdlhgv8o9mi22_d0a7\msg\file\2026-08\甬城圣杯战争｜全七卷完整版＋全女主爱情线.json';

void main() {
  test('自动识别并转换 SillyTavern chara_card_v2 文件', () async {
    final source = await File(_sillyTavernSample).readAsString();

    final converted = const ExternalJsonCardAdapter().convert(source);

    expect(converted.detectedFormat, contains('chara_card'));
    expect(converted.save.name, contains('无职转生'));
    expect(converted.save.characters, isNotEmpty);
    expect(converted.save.openingMessage.length, greaterThan(100));
    expect(converted.save.scenario, isNotEmpty);
  });

  test('存档导入器可直接把 SillyTavern 文件转换为新存档', () async {
    final source = await File(_sillyTavernSample).readAsString();

    final save = ExportService().decodeImportedSave(source);

    expect(save.id, isNotEmpty);
    expect(save.createdAt.year, 2026);
    expect(save.characters.single.description, isNotEmpty);
    expect(save.openingMessage.length, greaterThan(100));
  });

  test('剧情卡库与角色卡库也能读取 SillyTavern 文件', () async {
    final source = await File(_sillyTavernSample).readAsString();
    final service = ExportService();

    final storyCard = service.decodeImportedStoryCard(source);
    final character = service.decodeImportedCharacter(source);

    expect(storyCard.name, contains('无职转生'));
    expect(storyCard.template.openingMessage, isNotEmpty);
    expect(character.name, contains('无职转生'));
    expect(character.id, isNotEmpty);
  });

  test('原生方案A和大型完整剧情仍可直接导入', () async {
    final service = ExportService();
    final schemeA = service.decodeImportedSave(
      await File(_nativeSample).readAsString(),
    );
    final holyGrail = service.decodeImportedSave(
      await File(_largeNativeSample).readAsString(),
    );

    expect(schemeA.name, contains('无职转生'));
    expect(schemeA.lorebook, isNotEmpty);
    expect(holyGrail.name, contains('圣杯战争'));
    expect(holyGrail.characters.length, greaterThan(3));
  });

  test('兼容带对象式世界书词条的 TavernAI JSON', () {
    const source = '''{
      "name": "测试世界书",
      "entries": {
        "0": {
          "comment": "雾港",
          "key": ["雾港", "钟楼"],
          "content": "城市终年被浓雾覆盖。",
          "constant": true,
          "order": 42
        }
      }
    }''';

    final converted = const ExternalJsonCardAdapter().convert(source);

    expect(converted.save.lorebook.single.title, '雾港');
    expect(converted.save.lorebook.single.alwaysActive, isTrue);
    expect(converted.save.lorebook.single.keywords, contains('钟楼'));
  });
}
