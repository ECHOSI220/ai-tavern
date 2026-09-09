import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/api_profile.dart';
import '../models/card_build_target.dart';
import '../models/save_slot.dart';
import 'ai_card_builder_service.dart';

class AiJsonImportService {
  const AiJsonImportService(this._builderService);

  final AiCardBuilderService _builderService;

  Future<SaveSlot> convert({
    required ApiProfile profile,
    required String apiKey,
    required String uploadedJson,
  }) async {
    final officialSource = await rootBundle.loadString(
      'examples/white_echo_story_framework.ai-tavern.json',
    );
    final officialExample = jsonEncode(
      _compactExample(jsonDecode(officialSource), depth: 0),
    );
    final result = await _builderService.build(
      target: CardBuildTarget.story,
      profile: profile,
      apiKey: apiKey,
      additionalInstruction:
          '把待转换外部 JSON 转换并完善为完整剧情卡。必须保留原文件已有的人物、世界观、开场白、规则和世界书；不要把结构案例的角色或故事内容混入结果，案例只用于理解目标字段组织方式。',
      source:
          '''【幻境酒馆内置官方 JSON 结构案例（内容已缩短）】
$officialExample

【待转换外部 JSON】
$uploadedJson''',
    );
    final card = result.storyCard;
    if (card == null) throw const FormatException('AI 未能生成剧情卡格式');
    return card.createSave().copyWith(clearSourceStoryCardId: true);
  }

  Object? _compactExample(Object? value, {required int depth}) {
    if (depth >= 7) return '…';
    if (value is String) {
      return value.length > 160 ? '${value.substring(0, 160)}…' : value;
    }
    if (value is List) {
      return value
          .take(2)
          .map((item) => _compactExample(item, depth: depth + 1))
          .toList();
    }
    if (value is Map) {
      return value.map(
        (key, item) =>
            MapEntry(key.toString(), _compactExample(item, depth: depth + 1)),
      );
    }
    return value;
  }
}
