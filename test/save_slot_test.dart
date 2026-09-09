import 'package:ai_tavern/models/character.dart';
import 'package:ai_tavern/models/lore_entry.dart';
import 'package:ai_tavern/models/play_mode.dart';
import 'package:ai_tavern/models/save_slot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('存档 JSON 往返保留独立世界与角色资料', () {
    final save =
        SaveSlot.create(
          name: '银月酒馆',
          coverImage: r'C:\images\tavern.jpg',
          playerName: '旅行者',
          playerDescription: '一名失去记忆的年轻冒险者。',
          worldSetting: '艾尔西亚大陆。',
          scenario: '暴雨中推开酒馆大门。',
        ).copyWith(
          characters: const [
            Character(id: 'char-1', name: '莉娅', personality: '冷静、谨慎。'),
          ],
          lorebook: const [
            LoreEntry(
              id: 'lore-1',
              title: '银月酒馆',
              keywords: ['酒馆', '银月'],
              content: '地下室有一条秘密通道。',
            ),
          ],
          conversationMemory: '旅行者已经进入银月酒馆。',
          playMode: PlayMode.choice,
          choiceCount: 4,
          pendingChoices: const ['询问莉娅', '调查地下室', '观察窗外', '检查行囊'],
        );

    final restored = SaveSlot.fromJson(save.toJson());

    expect(restored.id, save.id);
    expect(restored.name, '银月酒馆');
    expect(restored.playerName, '旅行者');
    expect(restored.characters.single.name, '莉娅');
    expect(restored.lorebook.single.keywords, contains('银月'));
    expect(restored.messages, isEmpty);
    expect(restored.conversationMemory, contains('银月酒馆'));
    expect(restored.coverImage, endsWith('tavern.jpg'));
    expect(restored.playMode, PlayMode.choice);
    expect(restored.choiceCount, 4);
    expect(restored.pendingChoices, hasLength(4));
  });

  test('旧存档缺少玩法字段时兼容为普通玩法和默认六项', () {
    final json = SaveSlot.create(name: '旧存档').toJson()
      ..remove('playMode')
      ..remove('choiceCount')
      ..remove('pendingChoices');
    final restored = SaveSlot.fromJson(json);

    expect(restored.playMode, PlayMode.freeform);
    expect(restored.choiceCount, 6);
    expect(restored.pendingChoices, isEmpty);
  });
}
