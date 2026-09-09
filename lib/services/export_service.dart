import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/character.dart';
import '../models/save_slot.dart';
import '../models/story_card.dart';
import 'external_json_card_adapter.dart';

class ExportService {
  static const _uuid = Uuid();
  static const _externalAdapter = ExternalJsonCardAdapter();

  String encodeSave(SaveSlot save) => const JsonEncoder.withIndent(
    '  ',
  ).convert({'format': 'ai-tavern-save', 'version': 1, 'save': save.toJson()});

  SaveSlot decodeImportedSave(String source) {
    final decoded = jsonDecode(source);
    if (decoded is Map) {
      final map = decoded.cast<String, Object?>();
      final rawSave = map['save'];
      if (rawSave is Map) {
        return _reidentifySave(
          SaveSlot.fromJson(rawSave.cast<String, Object?>()),
        );
      }
      if (_looksLikeNativeSave(map)) {
        return _reidentifySave(SaveSlot.fromJson(map));
      }
    }
    return _externalAdapter.convert(source).save;
  }

  String encodeStoryCard(StoryCard card) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': 'ai-tavern-story-card',
        'version': 1,
        'storyCard': card.toJson(),
      });

  StoryCard decodeImportedStoryCard(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      final converted = _externalAdapter.convert(source);
      return StoryCard.fromSave(
        converted.save,
        description: converted.description,
        author: converted.author,
      );
    }
    final map = decoded.cast<String, Object?>();
    final now = DateTime.now();
    final rawCard = map['storyCard'];
    if (rawCard is Map) {
      final card = StoryCard.fromJson(rawCard.cast<String, Object?>());
      return card.copyWith(
        id: _uuid.v4(),
        isOfficial: false,
        createdAt: now,
        updatedAt: now,
      );
    }
    final rawSave = map['save'];
    if (rawSave is Map || _looksLikeNativeSave(map)) {
      return StoryCard.fromSave(
        SaveSlot.fromJson(
          (rawSave is Map ? rawSave : map).cast<String, Object?>(),
        ),
        description: '从存档 JSON 导入的剧情卡片',
      );
    }
    final converted = _externalAdapter.convert(source);
    return StoryCard.fromSave(
      converted.save,
      description: converted.description,
      author: converted.author,
    );
  }

  String encodeCharacter(Character character) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': 'ai-tavern-character',
        'version': 1,
        'character': character.toJson(),
      });

  Character decodeImportedCharacter(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      final converted = _externalAdapter.convert(source);
      if (converted.save.characters.isEmpty) {
        throw const FormatException('外部 JSON 中没有可导入的角色');
      }
      return converted.save.characters.first.copyWith(id: _uuid.v4());
    }
    final map = decoded.cast<String, Object?>();
    final raw = map['character'] ?? map;
    if (raw is! Map) throw const FormatException('找不到角色内容');
    if (!raw.containsKey('id')) {
      final converted = _externalAdapter.convert(source);
      if (converted.save.characters.isEmpty) {
        throw const FormatException('外部 JSON 中没有可导入的角色');
      }
      return converted.save.characters.first.copyWith(id: _uuid.v4());
    }
    return _reidentifyCharacter(
      Character.fromJson(raw.cast<String, Object?>()),
    );
  }

  Future<String?> exportSave(SaveSlot save) {
    return _saveJson(
      suggestedName: '${_safeFileName(save.name)}.json',
      content: encodeSave(save),
      dialogTitle: '导出存档',
    );
  }

  Future<String?> exportStoryCard(StoryCard card) {
    return _saveJson(
      suggestedName: '${_safeFileName(card.name)}.story-card.json',
      content: encodeStoryCard(card),
      dialogTitle: '导出剧情卡片',
    );
  }

  Future<String?> exportCharacter(Character character) {
    return _saveJson(
      suggestedName: '${_safeFileName(character.name)}.character.json',
      content: encodeCharacter(character),
      dialogTitle: '导出角色',
    );
  }

  Future<SaveSlot?> importSave() async {
    final source = await _pickJson(dialogTitle: '导入存档 JSON');
    return source == null ? null : decodeImportedSave(source);
  }

  Future<StoryCard?> importStoryCard() async {
    final source = await _pickJson(dialogTitle: '导入剧情卡片 JSON');
    return source == null ? null : decodeImportedStoryCard(source);
  }

  Future<Character?> importCharacter() async {
    final source = await _pickJson(dialogTitle: '导入角色 JSON');
    return source == null ? null : decodeImportedCharacter(source);
  }

  Future<String?> _saveJson({
    required String suggestedName,
    required String content,
    required String dialogTitle,
  }) {
    return FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: Uint8List.fromList(utf8.encode(content)),
      lockParentWindow: true,
    );
  }

  Future<String?> _pickJson({required String dialogTitle}) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
      withData: Platform.isAndroid,
      lockParentWindow: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.bytes != null) return utf8.decode(file.bytes!);
    if (file.path != null) return File(file.path!).readAsString();
    throw StateError('无法读取所选 JSON 文件');
  }

  Future<String?> pickJsonSource({required String dialogTitle}) =>
      _pickJson(dialogTitle: dialogTitle);

  bool _looksLikeNativeSave(Map<String, Object?> map) =>
      map.containsKey('id') &&
      map.containsKey('name') &&
      map.containsKey('createdAt') &&
      map.containsKey('updatedAt') &&
      map.containsKey('lastPlayedAt');

  SaveSlot _reidentifySave(SaveSlot source) {
    final now = DateTime.now();
    final saveId = _uuid.v4();
    final messageIds = {
      for (final message in source.messages) message.id: _uuid.v4(),
    };
    return source.copyWith(
      id: saveId,
      characters: source.characters.map(_reidentifyCharacter).toList(),
      lorebook: source.lorebook
          .map((entry) => entry.copyWith(id: _uuid.v4()))
          .toList(),
      messages: source.messages
          .map(
            (message) => message.copyWith(
              id: messageIds[message.id],
              saveId: saveId,
              parentMessageId: message.parentMessageId == null
                  ? null
                  : messageIds[message.parentMessageId],
            ),
          )
          .toList(),
      memorySummary: source.memorySummary.copyWith(
        coveredMessageId: source.memorySummary.coveredMessageId == null
            ? null
            : messageIds[source.memorySummary.coveredMessageId],
      ),
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
    );
  }

  Character _reidentifyCharacter(Character source) {
    final avatar = source.avatar;
    return Character(
      id: _uuid.v4(),
      name: source.name,
      avatar: avatar != null && File(avatar).existsSync() ? avatar : null,
      description: source.description,
      personality: source.personality,
      appearance: source.appearance,
      background: source.background,
      speakingStyle: source.speakingStyle,
      relationship: source.relationship,
      goals: source.goals,
      secrets: source.secrets,
      exampleDialogue: source.exampleDialogue,
      scenarioNotes: source.scenarioNotes,
      enabled: source.enabled,
    );
  }

  String _safeFileName(String value) {
    final result = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    return result.isEmpty ? 'ai-tavern' : result;
  }
}
