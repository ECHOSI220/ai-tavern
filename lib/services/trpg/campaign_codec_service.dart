import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import '../../models/campaign_models.dart';
import '../../models/trpg_models.dart';

class CampaignValidationIssue {
  const CampaignValidationIssue({
    required this.code,
    required this.message,
    this.isWarning = false,
  });
  final String code, message;
  final bool isWarning;
}

class CampaignValidationResult {
  const CampaignValidationResult(this.issues);
  final List<CampaignValidationIssue> issues;
  bool get isValid => issues.every((issue) => issue.isWarning);
  List<CampaignValidationIssue> get errors =>
      issues.where((issue) => !issue.isWarning).toList();
}

class CampaignCodecService {
  const CampaignCodecService();
  static const _uuid = Uuid();

  String exportCampaign(CampaignDocument campaign) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': 'ai-tavern-campaign',
        'schemaVersion': campaignSchemaVersion,
        'campaign': campaign.toJson(),
      });

  Future<String?> exportToFile(CampaignDocument campaign) =>
      FilePicker.platform.saveFile(
        dialogTitle: '导出跑团剧本',
        fileName: '${_safeName(campaign.title)}.campaign.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(exportCampaign(campaign))),
        lockParentWindow: true,
      );

  Future<CampaignDocument?> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入跑团剧本',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
      withData: Platform.isAndroid,
      lockParentWindow: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final source = file.bytes != null
        ? utf8.decode(file.bytes!)
        : await File(file.path!).readAsString();
    return importCampaign(source);
  }

  String _safeName(String value) {
    final result = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    return result.isEmpty ? 'campaign' : result;
  }

  CampaignDocument importCampaign(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (error) {
      throw FormatException('JSON 无法解析：$error');
    }
    if (decoded is! Map) throw const FormatException('剧本 JSON 顶层必须是对象');
    final root = decoded.cast<String, Object?>();
    final raw = root['campaign'] is Map
        ? (root['campaign'] as Map).cast<String, Object?>()
        : root;
    final migrated = migrateCampaign(raw);
    final result = CampaignDocument.fromJson(migrated).copyWith(
      id: _uuid.v4(),
      source: CampaignSourceType.imported,
      updatedAt: DateTime.now(),
    );
    final validation = validateCampaign(result);
    if (!validation.isValid) {
      throw FormatException(
        validation.errors.map((issue) => issue.message).join('；'),
      );
    }
    return result;
  }

  Map<String, Object?> migrateCampaign(Map<String, Object?> raw) {
    final version = (raw['schemaVersion'] as num?)?.toInt() ?? 1;
    if (version > campaignSchemaVersion) {
      throw FormatException('剧本版本 $version 高于当前支持版本 $campaignSchemaVersion');
    }
    if (version == campaignSchemaVersion) return raw;
    return {
      ...raw,
      'schemaVersion': campaignSchemaVersion,
      'source': raw['source'] ?? raw['sourceType'] ?? 'imported',
      'endings': raw['endings'] ?? raw['possibleEndings'] ?? const [],
      'acts': raw['acts'] ?? const [],
      'clues': raw['clues'] ?? const [],
      'aiGmSettings': raw['aiGmSettings'] ?? const {},
      'audioAssets': raw['audioAssets'] ?? const [],
      'presentationSettings': raw['presentationSettings'] ?? const {},
      'createdAt': raw['createdAt'] ?? DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  CampaignValidationResult validateCampaign(CampaignDocument campaign) {
    final issues = <CampaignValidationIssue>[];
    if (campaign.title.trim().isEmpty) {
      issues.add(
        const CampaignValidationIssue(code: 'title', message: '剧本名不能为空'),
      );
    }
    if (campaign.schemaVersion != campaignSchemaVersion) {
      issues.add(
        CampaignValidationIssue(
          code: 'schema_version',
          message: 'schemaVersion 必须为 $campaignSchemaVersion',
        ),
      );
    }
    final idOwners = <String, String>{};
    void register(String id, String label) {
      if (id.trim().isEmpty) {
        issues.add(
          CampaignValidationIssue(code: 'empty_id', message: '$label 缺少 ID'),
        );
      } else if (idOwners.containsKey(id)) {
        issues.add(
          CampaignValidationIssue(
            code: 'duplicate_id',
            message: '$label 与 ${idOwners[id]} 使用了重复 ID：$id',
          ),
        );
      } else {
        idOwners[id] = label;
      }
    }

    for (final location in campaign.locations) {
      register(location.id, '地点 ${location.name}');
      for (final marker in location.markers) {
        register(marker.id, '地图标记 ${marker.label}');
      }
    }
    for (final asset in campaign.audioAssets) {
      register(asset.id, '演出资源 ${asset.id}');
      if (RegExp(r'^[A-Za-z]:[/\\]').hasMatch(asset.path) ||
          asset.path.startsWith('/')) {
        issues.add(
          CampaignValidationIssue(
            code: 'absolute_asset_path',
            message: '资源 ${asset.id} 使用了绝对路径，导出前请改为 Campaign 相对资源 ID',
          ),
        );
      }
    }
    for (final npc in campaign.npcs) {
      register(npc.npcId, 'NPC ${npc.name}');
      if (npc.locationId != null &&
          !campaign.locations.any((value) => value.id == npc.locationId)) {
        issues.add(
          CampaignValidationIssue(
            code: 'npc_location',
            message: 'NPC ${npc.name} 引用了不存在的地点 ${npc.locationId}',
          ),
        );
      }
    }
    for (final clue in campaign.clues) {
      register(clue.id, '线索 ${clue.name}');
      for (final relation in clue.relations) {
        final valid = switch (relation.entityType) {
          'npc' => campaign.npcs.any(
            (value) => value.npcId == relation.entityId,
          ),
          'location' => campaign.locations.any(
            (value) => value.id == relation.entityId,
          ),
          'quest' => campaign.quests.any(
            (value) => value['id'] == relation.entityId,
          ),
          'clue' => campaign.clues.any(
            (value) => value.id == relation.entityId,
          ),
          _ => true,
        };
        if (!valid) {
          issues.add(
            CampaignValidationIssue(
              code: 'clue_reference',
              message:
                  '线索 ${clue.name} 引用了不存在的 ${relation.entityType}：${relation.entityId}',
            ),
          );
        }
      }
    }
    for (final quest in campaign.quests) {
      register(quest['id']?.toString() ?? '', '任务 ${quest['title'] ?? ''}');
    }

    final nodes = <String, StoryNode>{};
    for (final act in campaign.acts) {
      register(act.id, '幕 ${act.title}');
      for (final chapter in act.chapters) {
        register(chapter.id, '章节 ${chapter.title}');
        for (final node in chapter.storyNodes) {
          register(node.id, '剧情节点 ${node.title}');
          nodes[node.id] = node;
        }
      }
    }
    for (final node in nodes.values) {
      for (final next in node.nextNodes) {
        if (!nodes.containsKey(next)) {
          issues.add(
            CampaignValidationIssue(
              code: 'missing_story_node',
              message: '剧情节点 ${node.title} 指向不存在的节点 $next',
            ),
          );
        }
      }
      for (final prerequisite in node.prerequisites) {
        if (!nodes.containsKey(prerequisite)) {
          issues.add(
            CampaignValidationIssue(
              code: 'missing_prerequisite',
              message: '剧情节点 ${node.title} 的前置节点 $prerequisite 不存在',
            ),
          );
        }
      }
    }
    final visiting = <String>{};
    final visited = <String>{};
    bool hasCycle(String id) {
      if (visiting.contains(id)) return true;
      if (!visited.add(id)) return false;
      visiting.add(id);
      for (final next in nodes[id]?.nextNodes ?? const <String>[]) {
        if (nodes.containsKey(next) && hasCycle(next)) return true;
      }
      visiting.remove(id);
      return false;
    }

    if (nodes.keys.any(hasCycle)) {
      issues.add(
        const CampaignValidationIssue(
          code: 'cycle',
          message: '剧情节点存在循环引用，请确认这是刻意设计',
          isWarning: true,
        ),
      );
    }
    if (campaign.endings.isEmpty) {
      issues.add(
        const CampaignValidationIssue(
          code: 'no_ending',
          message: '剧本没有配置可达结局',
          isWarning: true,
        ),
      );
    }
    return CampaignValidationResult(issues);
  }
}
