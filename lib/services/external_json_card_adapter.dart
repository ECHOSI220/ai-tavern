import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/character.dart';
import '../models/lore_entry.dart';
import '../models/memory_summary.dart';
import '../models/play_mode.dart';
import '../models/save_slot.dart';

class ExternalJsonCardConversion {
  const ExternalJsonCardConversion({
    required this.save,
    required this.detectedFormat,
    this.author = '',
    this.description = '',
  });

  final SaveSlot save;
  final String detectedFormat;
  final String author;
  final String description;
}

class ExternalJsonCardAdapter {
  const ExternalJsonCardAdapter();

  static const _uuid = Uuid();

  ExternalJsonCardConversion convert(String source) {
    final decoded = jsonDecode(source);
    if (decoded is List) return _convertList(decoded);
    if (decoded is! Map) {
      throw const FormatException('JSON 根节点不是可识别的对象或数组');
    }
    final root = decoded.cast<String, Object?>();
    if (_looksLikeSillyTavernCharacter(root)) {
      return _convertSillyTavernCharacter(root);
    }
    if (_looksLikeWorldBook(root)) return _convertWorldBook(root);
    throw FormatException(
      '无法识别外部 JSON 格式；根字段：${root.keys.take(12).join(', ')}',
    );
  }

  ExternalJsonCardConversion _convertList(List<Object?> source) {
    final maps = source.whereType<Map>().toList();
    if (maps.isEmpty) throw const FormatException('JSON 数组中没有可识别的卡片内容');
    final first = maps.first.cast<String, Object?>();
    if (_looksLikeSillyTavernCharacter(first)) {
      return _convertSillyTavernCharacter(first);
    }
    final entries = maps
        .map((item) => _loreFromMap(item.cast<String, Object?>()))
        .whereType<LoreEntry>()
        .toList();
    if (entries.isNotEmpty) return _worldBookConversion(entries, '外部世界书数组');
    throw const FormatException('JSON 数组不是可识别的角色卡或世界书');
  }

  bool _looksLikeSillyTavernCharacter(Map<String, Object?> root) {
    final data = _map(root['data']);
    final spec = _text(root['spec']).toLowerCase();
    return spec.contains('chara_card') ||
        root.containsKey('first_mes') ||
        root.containsKey('mes_example') ||
        data.containsKey('first_mes') ||
        data.containsKey('character_book');
  }

  bool _looksLikeWorldBook(Map<String, Object?> root) {
    return root.containsKey('entries') ||
        root.containsKey('world_info') ||
        root.containsKey('worldbook') ||
        root.containsKey('character_book');
  }

  ExternalJsonCardConversion _convertSillyTavernCharacter(
    Map<String, Object?> root,
  ) {
    final nested = _map(root['data']);
    final data = nested.isEmpty ? root : {...root, ...nested};
    final now = DateTime.now();
    final name = _text(data['name'], fallback: '外部角色卡');
    final description = _text(data['description']);
    final personality = _text(data['personality']);
    final scenario = _text(data['scenario']);
    final opening = _text(data['first_mes'] ?? data['firstMessage']);
    final examples = _text(data['mes_example'] ?? data['example_dialogue']);
    final creatorNotes = _text(
      data['creator_notes'] ?? root['creatorcomment'] ?? data['creatorcomment'],
    );
    final systemPrompt = _text(data['system_prompt'] ?? data['systemPrompt']);
    final postHistory = _text(
      data['post_history_instructions'] ?? data['postHistoryInstructions'],
    );
    final author = _text(data['creator'] ?? root['creator']);
    final alternateGreetings = _strings(
      data['alternate_greetings'] ?? data['alternateGreetings'],
    );
    final lorebook = <LoreEntry>[
      ..._extractLore(data['character_book'] ?? data['characterBook']),
      ..._extractLore(data['world_info'] ?? data['worldInfo']),
      ..._extractLore(data['worldbook']),
    ];
    if (alternateGreetings.isNotEmpty) {
      lorebook.add(
        LoreEntry(
          id: _uuid.v4(),
          title: '备选开场白',
          keywords: const [],
          content: alternateGreetings
              .asMap()
              .entries
              .map((entry) => '开场 ${entry.key + 1}：${entry.value}')
              .join('\n\n'),
          alwaysActive: false,
          priority: -100,
        ),
      );
    }

    final isRpgHost =
        name.toLowerCase().contains('rpg') ||
        lorebook.isNotEmpty ||
        _strings(data['tags']).any((tag) => tag.toLowerCase().contains('rpg'));
    final character = Character(
      id: _uuid.v4(),
      name: name,
      description: isRpgHost && description.length > 1200
          ? '由外部 SillyTavern 角色卡导入的剧情主持角色，完整设定已保存在世界观中。'
          : description,
      personality: personality,
      background: creatorNotes,
      speakingStyle: _text(data['speaking_style']),
      relationship: _text(data['relationship']),
      goals: _text(data['goals']),
      secrets: _text(data['secrets']),
      exampleDialogue: examples,
      scenarioNotes: scenario,
    );
    final ruleParts = [
      defaultRoleplayRules,
      systemPrompt,
      postHistory,
    ].where((item) => item.trim().isNotEmpty).toList();
    final worldSetting = isRpgHost
        ? description
        : lorebook
              .where((entry) => entry.alwaysActive)
              .map((entry) => '${entry.title}：${entry.content}')
              .join('\n\n');
    final save = SaveSlot(
      id: _uuid.v4(),
      name: name,
      scenario: scenario.isEmpty ? description : scenario,
      worldSetting: worldSetting,
      roleplayRules: ruleParts.join('\n\n'),
      openingMessage: opening,
      characters: [character],
      lorebook: _deduplicateLore(lorebook),
      playMode: PlayMode.freeform,
      memorySummary: MemorySummary(updatedAt: now),
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
    );
    return ExternalJsonCardConversion(
      save: save,
      detectedFormat: _text(
        root['spec'],
        fallback: 'SillyTavern / TavernAI 角色卡',
      ),
      author: author,
      description: scenario.isEmpty ? _excerpt(description) : scenario,
    );
  }

  ExternalJsonCardConversion _convertWorldBook(Map<String, Object?> root) {
    final entries = <LoreEntry>[
      ..._extractLore(root),
      ..._extractLore(root['world_info']),
      ..._extractLore(root['worldbook']),
      ..._extractLore(root['character_book']),
    ];
    if (entries.isEmpty) throw const FormatException('世界书中没有可读取的词条');
    return _worldBookConversion(
      _deduplicateLore(entries),
      'SillyTavern / TavernAI 世界书',
      name: _text(root['name'], fallback: '导入世界书'),
    );
  }

  ExternalJsonCardConversion _worldBookConversion(
    List<LoreEntry> entries,
    String format, {
    String name = '导入世界书',
  }) {
    final now = DateTime.now();
    return ExternalJsonCardConversion(
      detectedFormat: format,
      description: '从外部格式导入 ${entries.length} 条世界书词条',
      save: SaveSlot(
        id: _uuid.v4(),
        name: name,
        scenario: '使用导入的世界书开始自由角色扮演。',
        lorebook: entries,
        memorySummary: MemorySummary(updatedAt: now),
        createdAt: now,
        updatedAt: now,
        lastPlayedAt: now,
      ),
    );
  }

  List<LoreEntry> _extractLore(Object? raw) {
    if (raw == null) return const [];
    Object? entries = raw;
    if (raw is Map) {
      final map = raw.cast<Object?, Object?>();
      entries = map['entries'] ?? map['data'] ?? map['items'] ?? raw;
    }
    final candidates = <Map<String, Object?>>[];
    if (entries is List) {
      candidates.addAll(
        entries.whereType<Map>().map((item) => item.cast<String, Object?>()),
      );
    } else if (entries is Map) {
      final map = entries.cast<Object?, Object?>();
      if (_looksLikeLoreEntry(map)) {
        candidates.add(map.map((key, value) => MapEntry('$key', value)));
      } else {
        candidates.addAll(
          map.values.whereType<Map>().map(
            (item) => item.cast<String, Object?>(),
          ),
        );
      }
    }
    return candidates.map(_loreFromMap).whereType<LoreEntry>().toList();
  }

  bool _looksLikeLoreEntry(Map<Object?, Object?> map) =>
      map.containsKey('content') ||
      map.containsKey('key') ||
      map.containsKey('keys');

  LoreEntry? _loreFromMap(Map<String, Object?> data) {
    final content = _text(
      data['content'] ?? data['text'] ?? data['value'] ?? data['description'],
    );
    if (content.isEmpty) return null;
    final disabled = _boolean(data['disable'] ?? data['disabled'], false);
    final enabled = _boolean(data['enabled'], !disabled);
    final title = _text(
      data['name'] ?? data['comment'] ?? data['title'] ?? data['uid'],
      fallback: '世界书词条',
    );
    final keywords = <String>{
      ..._strings(data['keys'] ?? data['key'] ?? data['keywords']),
      ..._strings(data['secondary_keys'] ?? data['keysecondary']),
    }.toList();
    return LoreEntry(
      id: _uuid.v4(),
      title: title,
      keywords: keywords,
      content: content,
      alwaysActive: _boolean(
        data['constant'] ?? data['alwaysActive'] ?? data['always_active'],
        false,
      ),
      enabled: enabled,
      priority: _integer(
        data['insertion_order'] ?? data['order'] ?? data['priority'],
        0,
      ).clamp(-1000, 1000),
    );
  }

  List<LoreEntry> _deduplicateLore(List<LoreEntry> entries) {
    final seen = <String>{};
    return entries.where((entry) {
      final key = '${entry.title}\u0000${entry.content}'.toLowerCase();
      return seen.add(key);
    }).toList();
  }

  Map<String, Object?> _map(Object? value) => value is Map
      ? value.map((key, value) => MapEntry('$key', value))
      : const {};

  String _text(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    final result = value is String ? value.trim() : value.toString().trim();
    return result.isEmpty ? fallback : result;
  }

  List<String> _strings(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String) {
      return value
          .split(RegExp(r'[,，、\n]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  bool _boolean(Object? value, bool fallback) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      if (value.toLowerCase() == 'true') return true;
      if (value.toLowerCase() == 'false') return false;
    }
    return fallback;
  }

  int _integer(Object? value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _excerpt(String value) =>
      value.length > 180 ? '${value.substring(0, 180)}…' : value;
}
