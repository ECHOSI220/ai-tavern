import 'package:ai_tavern/models/character.dart';
import 'package:ai_tavern/models/chat_message.dart';
import 'package:ai_tavern/models/save_slot.dart';
import 'package:ai_tavern/services/export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('导入存档重建所有跨存档关键 ID', () {
    final now = DateTime.utc(2026, 8, 10);
    final source = SaveSlot.create(name: '银月酒馆').copyWith(
      characters: const [Character(id: 'c1', name: '莉娅')],
      messages: [
        ChatMessage(
          id: 'm1',
          saveId: 'old-save',
          role: ChatRole.user,
          content: '我推开大门。',
          createdAt: now,
          updatedAt: now,
        ),
        ChatMessage(
          id: 'm2',
          saveId: 'old-save',
          role: ChatRole.assistant,
          content: '欢迎来到银月。',
          createdAt: now,
          updatedAt: now,
          parentMessageId: 'm1',
        ),
      ],
    );
    final service = ExportService();

    final imported = service.decodeImportedSave(service.encodeSave(source));

    expect(imported.id, isNot(source.id));
    expect(imported.characters.single.id, isNot('c1'));
    expect(imported.messages.map((message) => message.saveId), {imported.id});
    expect(imported.messages[1].parentMessageId, imported.messages[0].id);
  });
}
