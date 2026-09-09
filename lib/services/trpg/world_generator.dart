import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../models/api_profile.dart';
import '../../models/campaign_models.dart';
import '../../models/trpg_game_models.dart';
import '../../models/trpg_models.dart';
import '../../models/trpg_party_models.dart';
import '../../models/trpg_world_generator_models.dart';
import '../ai_service.dart';
import 'ai_campaign_generator.dart';
import 'living_npc_service.dart';
import 'faction_simulation_service.dart';

const worldGenerationSchemaVersion = 1;

class WorldValidationIssue {
  const WorldValidationIssue({
    required this.code,
    required this.message,
    this.warning = false,
  });

  final String code;
  final String message;
  final bool warning;
}

class WorldValidationResult {
  const WorldValidationResult(this.issues);

  final List<WorldValidationIssue> issues;
  bool get isValid => issues.every((item) => item.warning);
  List<WorldValidationIssue> get errors =>
      issues.where((item) => !item.warning).toList();
}

class WorldGenerationResult {
  const WorldGenerationResult({
    required this.seed,
    required this.blueprint,
    required this.campaign,
    required this.state,
    required this.validation,
  });

  final WorldSeed seed;
  final WorldBlueprint blueprint;
  final CampaignDocument campaign;
  final WorldGenerationState state;
  final WorldValidationResult validation;
}

class WorldValidator {
  const WorldValidator();

  WorldValidationResult validate(WorldBlueprint blueprint) {
    final issues = <WorldValidationIssue>[];
    final locationIds = <String>{};
    final npcIds = <String>{};
    final factionIds = <String>{};
    final questIds = <String>{};

    void unique(Set<String> target, String id, String label) {
      if (id.trim().isEmpty) {
        issues.add(
          WorldValidationIssue(code: 'empty_id', message: '$label 缺少 ID'),
        );
      } else if (!target.add(id)) {
        issues.add(
          WorldValidationIssue(
            code: 'duplicate_id',
            message: '$label ID 重复：$id',
          ),
        );
      }
    }

    if (blueprint.worldName.trim().isEmpty) {
      issues.add(
        const WorldValidationIssue(code: 'world_name', message: '世界名称不能为空'),
      );
    }
    if (blueprint.locations.isEmpty) {
      issues.add(
        const WorldValidationIssue(
          code: 'locations_empty',
          message: '世界至少需要一个地点',
        ),
      );
    }
    for (final location in blueprint.locations) {
      unique(locationIds, location.id, '地点 ${location.name}');
    }
    for (final location in blueprint.locations) {
      if (location.parentLocation != null &&
          !locationIds.contains(location.parentLocation)) {
        issues.add(
          WorldValidationIssue(
            code: 'location_parent',
            message: '地点 ${location.name} 的父地点不存在',
          ),
        );
      }
      for (final connected in location.connectedLocations) {
        if (!locationIds.contains(connected)) {
          issues.add(
            WorldValidationIssue(
              code: 'location_connection',
              message: '地点 ${location.name} 连接到不存在的地点 $connected',
            ),
          );
        }
      }
    }
    if (blueprint.locations.length > 1 && !_isConnected(blueprint.locations)) {
      issues.add(
        const WorldValidationIssue(
          code: 'disconnected_map',
          message: '地点图存在无法到达的孤立区域',
        ),
      );
    }

    for (final npc in blueprint.npcs) {
      unique(npcIds, npc.id, 'NPC ${npc.name}');
      if (!locationIds.contains(npc.locationId)) {
        issues.add(
          WorldValidationIssue(
            code: 'npc_location',
            message: 'NPC ${npc.name} 的地点不存在',
          ),
        );
      }
    }
    final mainNpcCount = blueprint.npcs
        .where((item) => item.rank == GeneratedNpcRank.main)
        .length;
    final importantNpcCount = blueprint.npcs
        .where((item) => item.rank == GeneratedNpcRank.important)
        .length;
    if (mainNpcCount < 5 || mainNpcCount > 10) {
      issues.add(
        WorldValidationIssue(
          code: 'main_npc_ratio',
          message: '主要 NPC 建议保持 5~10 个，当前为 $mainNpcCount 个',
          warning: true,
        ),
      );
    }
    if (importantNpcCount < 20 || importantNpcCount > 50) {
      issues.add(
        WorldValidationIssue(
          code: 'important_npc_ratio',
          message: '完整战役的重要 NPC 建议保持 20~50 个，当前为 $importantNpcCount 个',
          warning: true,
        ),
      );
    }
    for (final faction in blueprint.factions) {
      unique(factionIds, faction.id, '势力 ${faction.name}');
      if (faction.territoryLocationIds.isEmpty ||
          faction.territoryLocationIds.any(
            (location) => !locationIds.contains(location),
          )) {
        issues.add(
          WorldValidationIssue(
            code: 'faction_territory',
            message: '势力 ${faction.name} 没有有效基地或领地',
          ),
        );
      }
      if (!npcIds.contains(faction.leaderNpcId)) {
        issues.add(
          WorldValidationIssue(
            code: 'faction_leader',
            message: '势力 ${faction.name} 的领袖不存在',
          ),
        );
      }
    }
    for (final relation in blueprint.factionRelationships) {
      if (!factionIds.contains(relation.fromFactionId) ||
          !factionIds.contains(relation.toFactionId)) {
        issues.add(
          const WorldValidationIssue(
            code: 'faction_relation',
            message: '势力关系引用了不存在的势力',
          ),
        );
      }
    }
    for (final npc in blueprint.npcs) {
      if (npc.factionId != null && !factionIds.contains(npc.factionId)) {
        issues.add(
          WorldValidationIssue(
            code: 'npc_faction',
            message: 'NPC ${npc.name} 的势力不存在',
          ),
        );
      }
    }
    for (final quest in blueprint.quests) {
      unique(questIds, quest.id, '任务 ${quest.title}');
      if (!npcIds.contains(quest.giverNpcId)) {
        issues.add(
          WorldValidationIssue(
            code: 'quest_giver',
            message: '任务 ${quest.title} 的发布者不存在',
          ),
        );
      }
      if (!locationIds.contains(quest.locationId)) {
        issues.add(
          WorldValidationIssue(
            code: 'quest_location',
            message: '任务 ${quest.title} 的地点不存在',
          ),
        );
      }
      if (quest.branches.length < 2) {
        issues.add(
          WorldValidationIssue(
            code: 'quest_branches',
            message: '任务 ${quest.title} 缺少多结局分支',
            warning: true,
          ),
        );
      }
    }
    for (final quest in blueprint.quests) {
      for (final prerequisite in quest.prerequisiteQuestIds) {
        if (!questIds.contains(prerequisite)) {
          issues.add(
            WorldValidationIssue(
              code: 'quest_prerequisite',
              message: '任务 ${quest.title} 的前置任务不存在：$prerequisite',
            ),
          );
        }
      }
    }
    final contentIds = <String>{};
    for (final item in blueprint.items) {
      unique(
        contentIds,
        item['id']?.toString() ?? '',
        '物品 ${item['name'] ?? ''}',
      );
    }
    for (final enemy in blueprint.enemies) {
      unique(contentIds, enemy.id, '敌人生态 ${enemy.name}');
      if (enemy.regionLocationIds.isEmpty ||
          enemy.regionLocationIds.any((id) => !locationIds.contains(id))) {
        issues.add(
          WorldValidationIssue(
            code: 'enemy_region',
            message: '敌人生态 ${enemy.name} 没有有效活动区域',
          ),
        );
      }
    }
    for (final secret in blueprint.secrets) {
      unique(contentIds, secret.id, '秘密 ${secret.title}');
      final owner = secret.ownerEntityId;
      if (owner != null &&
          !npcIds.contains(owner) &&
          !factionIds.contains(owner) &&
          !locationIds.contains(owner) &&
          !questIds.contains(owner)) {
        issues.add(
          WorldValidationIssue(
            code: 'secret_owner',
            message: '秘密 ${secret.title} 的所属实体不存在',
          ),
        );
      }
    }
    for (final event in blueprint.history) {
      if (event.affectedRegions.any((id) => !locationIds.contains(id))) {
        issues.add(
          WorldValidationIssue(
            code: 'history_region',
            message: '历史事件 ${event.eventId} 引用了不存在的地区',
          ),
        );
      }
    }
    final start = blueprint.startingScenario;
    if (!locationIds.contains(start.locationId)) {
      issues.add(
        const WorldValidationIssue(code: 'start_location', message: '开局地点不存在'),
      );
    }
    if (start.npcIds.any((id) => !npcIds.contains(id))) {
      issues.add(
        const WorldValidationIssue(
          code: 'start_npc',
          message: '开局事件引用了不存在的 NPC',
        ),
      );
    }
    if (blueprint.history.any(
      (item) => item.time.trim().isEmpty || item.description.trim().isEmpty,
    )) {
      issues.add(
        const WorldValidationIssue(
          code: 'timeline',
          message: '世界历史存在缺少时间或内容的事件',
        ),
      );
    }
    return WorldValidationResult(issues);
  }

  WorldBlueprint repair(WorldBlueprint source) {
    var locations = source.locations;
    if (locations.isEmpty) {
      locations = const [
        LocationDefinition(
          id: 'start',
          name: '起点聚落',
          description: '冒险者进入世界的安全据点。',
          type: GeneratedLocationType.village,
        ),
      ];
    }
    final locationIds = locations.map((item) => item.id).toSet();
    final repairedLocations = <LocationDefinition>[];
    for (var index = 0; index < locations.length; index++) {
      final location = locations[index];
      final validConnections = location.connectedLocations
          .where(locationIds.contains)
          .where((id) => id != location.id)
          .toSet();
      if (index > 0) validConnections.add(locations[index - 1].id);
      if (index < locations.length - 1) {
        validConnections.add(locations[index + 1].id);
      }
      repairedLocations.add(
        location.copyWith(
          parentLocation:
              location.parentLocation != null &&
                  locationIds.contains(location.parentLocation)
              ? location.parentLocation
              : null,
          connectedLocations: validConnections.toList(),
        ),
      );
    }
    locations = repairedLocations;
    final fallbackLocation = locations.first.id;

    var npcs = source.npcs;
    if (npcs.isEmpty) {
      npcs = [
        GeneratedNpcDefinition(
          id: 'npc_guide',
          name: '引路人',
          age: 35,
          role: '引路人与委托人',
          personality: '谨慎、务实',
          goal: '帮助冒险者理解当前危机',
          locationId: fallbackLocation,
          rank: GeneratedNpcRank.main,
        ),
      ];
    }
    npcs = npcs
        .map(
          (npc) => GeneratedNpcDefinition(
            id: npc.id,
            name: npc.name,
            age: npc.age,
            role: npc.role,
            personality: npc.personality,
            goal: npc.goal,
            secret: npc.secret,
            locationId: locationIds.contains(npc.locationId)
                ? npc.locationId
                : fallbackLocation,
            factionId: npc.factionId,
            rank: npc.rank,
            relationships: npc.relationships,
            tags: npc.tags,
          ),
        )
        .toList();
    final npcIds = npcs.map((item) => item.id).toSet();

    var factions = source.factions;
    if (factions.isEmpty) {
      factions = [
        FactionDefinition(
          id: 'faction_local',
          name: '本地共同体',
          goal: '维持聚落生存',
          leaderNpcId: npcs.first.id,
          territoryLocationIds: [fallbackLocation],
        ),
      ];
    }
    factions = factions
        .map(
          (faction) => FactionDefinition(
            id: faction.id,
            name: faction.name,
            goal: faction.goal,
            leaderNpcId: npcIds.contains(faction.leaderNpcId)
                ? faction.leaderNpcId
                : npcs.first.id,
            territoryLocationIds:
                faction.territoryLocationIds.where(locationIds.contains).isEmpty
                ? [fallbackLocation]
                : faction.territoryLocationIds
                      .where(locationIds.contains)
                      .toList(),
            resources: faction.resources,
            secret: faction.secret,
            tags: faction.tags,
          ),
        )
        .toList();
    final factionIds = factions.map((item) => item.id).toSet();
    npcs = npcs
        .map(
          (npc) => GeneratedNpcDefinition(
            id: npc.id,
            name: npc.name,
            age: npc.age,
            role: npc.role,
            personality: npc.personality,
            goal: npc.goal,
            secret: npc.secret,
            locationId: npc.locationId,
            factionId:
                npc.factionId != null && factionIds.contains(npc.factionId)
                ? npc.factionId
                : null,
            rank: npc.rank,
            relationships: npc.relationships,
            tags: npc.tags,
          ),
        )
        .toList();

    final questIds = source.quests.map((item) => item.id).toSet();
    final quests = source.quests
        .map(
          (quest) => GeneratedQuestDefinition(
            id: quest.id,
            title: quest.title,
            description: quest.description,
            giverNpcId: npcIds.contains(quest.giverNpcId)
                ? quest.giverNpcId
                : npcs.first.id,
            locationId: locationIds.contains(quest.locationId)
                ? quest.locationId
                : fallbackLocation,
            objectives: quest.objectives,
            rewards: quest.rewards,
            failure: quest.failure,
            branches: quest.branches,
            prerequisiteQuestIds: quest.prerequisiteQuestIds
                .where(questIds.contains)
                .toList(),
          ),
        )
        .toList();
    final validSecretOwners = <String>{
      ...locationIds,
      ...npcIds,
      ...factionIds,
      ...questIds,
    };
    final enemies = source.enemies
        .map(
          (enemy) => EnemyEcologyDefinition(
            id: enemy.id,
            name: enemy.name,
            regionLocationIds:
                enemy.regionLocationIds.where(locationIds.contains).isEmpty
                ? [fallbackLocation]
                : enemy.regionLocationIds.where(locationIds.contains).toList(),
            behavior: enemy.behavior,
            population: enemy.population,
            weaknesses: enemy.weaknesses,
            origin: enemy.origin,
            dangerLevel: enemy.dangerLevel,
          ),
        )
        .toList();
    final secrets = source.secrets
        .map(
          (secret) => WorldSecretDefinition(
            id: secret.id,
            title: secret.title,
            content: secret.content,
            scope: secret.scope,
            ownerEntityId:
                secret.ownerEntityId != null &&
                    validSecretOwners.contains(secret.ownerEntityId)
                ? secret.ownerEntityId
                : null,
            knownByEntityIds: secret.knownByEntityIds
                .where(validSecretOwners.contains)
                .toList(),
            revealed: secret.revealed,
          ),
        )
        .toList();
    final history = source.history
        .map(
          (event) => WorldHistoryEvent(
            eventId: event.eventId,
            time: event.time.trim().isEmpty ? '未知时代' : event.time,
            description: event.description.trim().isEmpty
                ? '一段记录不完整的历史事件。'
                : event.description,
            importance: event.importance,
            affectedRegions:
                event.affectedRegions.where(locationIds.contains).isEmpty
                ? [fallbackLocation]
                : event.affectedRegions.where(locationIds.contains).toList(),
          ),
        )
        .toList();
    final start = source.startingScenario;
    return source.copyWith(
      locations: locations,
      factions: factions,
      factionRelationships: source.factionRelationships
          .where(
            (item) =>
                factionIds.contains(item.fromFactionId) &&
                factionIds.contains(item.toFactionId),
          )
          .toList(),
      npcs: npcs,
      quests: quests,
      enemies: enemies,
      secrets: secrets,
      history: history,
      startingScenario: StartingScenarioDefinition(
        locationId: locationIds.contains(start.locationId)
            ? start.locationId
            : fallbackLocation,
        npcIds: start.npcIds.where(npcIds.contains).isEmpty
            ? [npcs.first.id]
            : start.npcIds.where(npcIds.contains).toList(),
        conflict: start.conflict,
        playerGoal: start.playerGoal,
        opening: start.opening,
      ),
      generationNotes: {
        ...source.generationNotes,
        'autoRepaired': true,
        'repairedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  bool _isConnected(List<LocationDefinition> locations) {
    if (locations.isEmpty) return true;
    final graph = {
      for (final location in locations)
        location.id: <String>{...location.connectedLocations},
    };
    for (final location in locations) {
      for (final neighbor in location.connectedLocations) {
        graph[neighbor]?.add(location.id);
      }
    }
    final visited = <String>{};
    final queue = <String>[locations.first.id];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (!visited.add(current)) continue;
      queue.addAll(graph[current] ?? const <String>{});
    }
    return visited.length == locations.length;
  }
}

class WorldGenerator {
  // The public parameter name is intentionally different from the private field.
  // ignore: prefer_initializing_formals
  WorldGenerator({AiService? aiService}) : _aiService = aiService;

  final AiService? _aiService;
  static const _uuid = Uuid();
  static const _validator = WorldValidator();

  Future<WorldGenerationResult> generate({
    required WorldSeed seed,
    ApiProfile? profile,
    String? apiKey,
    void Function(String stage, double progress)? onProgress,
  }) async {
    if (seed.isEmpty) throw ArgumentError('theme 或 genre 至少填写一项');
    WorldBlueprint blueprint;
    if (_aiService != null && profile != null && apiKey != null) {
      blueprint = await _generateWithAi(
        seed: seed,
        profile: profile,
        apiKey: apiKey,
        onProgress: onProgress,
      );
    } else {
      onProgress?.call('正在生成离线世界骨架', .15);
      blueprint = generateLocalBlueprint(seed);
    }
    onProgress?.call('正在检查世界一致性', .86);
    var validation = _validator.validate(blueprint);
    if (!validation.isValid) {
      blueprint = _validator.repair(blueprint);
      validation = _validator.validate(blueprint);
    }
    if (!validation.isValid) {
      throw FormatException(
        validation.errors.map((item) => item.message).join('；'),
      );
    }
    final generationId = _uuid.v4();
    final state = WorldGenerationState(
      seed: seed,
      blueprint: blueprint,
      generatedData: {
        'createdAt': DateTime.now().toIso8601String(),
        'mode': _aiService == null ? 'local' : 'ai',
        'lazyNpcEnabled': true,
      },
      generationVersion: worldGenerationSchemaVersion,
      generationId: generationId,
      generatedLocationIds: [blueprint.startingScenario.locationId],
    );
    final campaign = toCampaignDocument(seed, blueprint, state);
    onProgress?.call('世界生成完成，可进入编辑器修改', 1);
    return WorldGenerationResult(
      seed: seed,
      blueprint: blueprint,
      campaign: campaign,
      state: state,
      validation: validation,
    );
  }

  WorldBlueprint generateLocalBlueprint(WorldSeed seed) {
    final profile = _localTheme(seed);
    final locationCount = switch (seed.level) {
      WorldGenerationLevel.quick => 4,
      WorldGenerationLevel.normal => 7,
      WorldGenerationLevel.detailed => 10,
    };
    final mainCount = switch (seed.level) {
      WorldGenerationLevel.quick => 5,
      WorldGenerationLevel.normal => 6,
      WorldGenerationLevel.detailed => 10,
    };
    final importantCount = switch (seed.level) {
      WorldGenerationLevel.quick => 6,
      WorldGenerationLevel.normal => 20,
      WorldGenerationLevel.detailed => 35,
    };
    final locations = <LocationDefinition>[];
    for (var index = 0; index < locationCount; index++) {
      final name = profile.locations[index % profile.locations.length];
      locations.add(
        LocationDefinition(
          id: 'location_${index + 1}',
          name: name,
          description: '${seed.theme}世界中的$name，连接着当前危机与可自由探索的线索。',
          type: index == 0
              ? GeneratedLocationType.city
              : index % 3 == 0
              ? GeneratedLocationType.dungeon
              : GeneratedLocationType.site,
          parentLocation: index == 0 ? null : 'location_1',
          connectedLocations: [
            if (index > 0) 'location_$index',
            if (index < locationCount - 1) 'location_${index + 2}',
          ],
          background:
              '${seed.era} · ${seed.technologyLevel} · ${seed.magicLevel}',
          population: index == 0 ? 12000 : 200 * (index + 1),
          dangerLevel: (15 + index * 8).clamp(0, 100),
          resources: profile.resources,
          tags: [seed.genre, ...seed.keywords.take(2)],
          hidden: index == locationCount - 1,
        ),
      );
    }
    final npcs = <GeneratedNpcDefinition>[];
    for (var index = 0; index < mainCount + importantCount; index++) {
      npcs.add(
        GeneratedNpcDefinition(
          id: 'npc_${index + 1}',
          name: profile.npcs[index % profile.npcs.length],
          age: 22 + (index * 5) % 45,
          role: index == 0
              ? '引路人与委托人'
              : profile.roles[index % profile.roles.length],
          personality: index.isEven ? '冷静、克制、重视承诺' : '果断、怀疑、善于观察',
          goal: index == 0 ? '查明正在扩大的世界危机' : '保护自身势力并获得关键资源',
          secret: index.isOdd ? '掌握一段会改变阵营关系的隐秘历史。' : '',
          locationId: 'location_${(index % locationCount) + 1}',
          factionId: 'faction_${(index % 3) + 1}',
          rank: index < mainCount
              ? GeneratedNpcRank.main
              : GeneratedNpcRank.important,
          tags: [seed.tone, profile.roles[index % profile.roles.length]],
        ),
      );
    }
    final factions = List.generate(
      3,
      (index) => FactionDefinition(
        id: 'faction_${index + 1}',
        name: profile.factions[index],
        goal: profile.factionGoals[index],
        leaderNpcId: npcs[index].id,
        territoryLocationIds: ['location_${index + 1}'],
        resources: profile.resources,
        secret: index == 2 ? '该势力暗中保存着旧时代灾难的真实记录。' : '',
        tags: [seed.genre, index == 0 ? '秩序' : '竞争'],
      ),
    );
    final quests = List.generate(
      seed.level == WorldGenerationLevel.quick ? 3 : 5,
      (index) => GeneratedQuestDefinition(
        id: 'quest_${index + 1}',
        title: profile.quests[index % profile.quests.length],
        description:
            '调查${locations[(index + 1) % locations.length].name}中的异常，并决定真相如何影响世界。',
        giverNpcId: npcs[index % npcs.length].id,
        locationId: locations[(index + 1) % locations.length].id,
        objectives: ['取得可靠线索', '与相关 NPC 交涉', '决定事件的处理方式'],
        rewards: ['势力信任', profile.resources[index % profile.resources.length]],
        failure: '危机扩大，相关势力获得先机。',
        branches: const [
          {'id': 'rescue', 'title': '救援并公开真相', 'ending': '关系改善但引发公开冲突'},
          {'id': 'conceal', 'title': '隐瞒并交换利益', 'ending': '获得资源但留下长期隐患'},
          {'id': 'oppose', 'title': '拒绝双方方案', 'ending': '开启独立调查路线'},
        ],
        prerequisiteQuestIds: index == 0 ? const [] : ['quest_$index'],
      ),
    );
    return WorldBlueprint(
      worldName: profile.worldName,
      summary:
          '${seed.tone}风格的${seed.theme}${seed.genre}世界。多个势力围绕${profile.crisis}展开竞争，玩家可以自由选择路线。',
      history: [
        WorldHistoryEvent(
          eventId: 'history_1',
          time: '200年前',
          description: profile.oldHistory,
          importance: 9,
          affectedRegions: locations.take(3).map((item) => item.id).toList(),
        ),
        WorldHistoryEvent(
          eventId: 'history_2',
          time: '50年前',
          description: profile.recentHistory,
          importance: 7,
          affectedRegions: locations
              .skip(1)
              .take(3)
              .map((item) => item.id)
              .toList(),
        ),
        WorldHistoryEvent(
          eventId: 'history_3',
          time: '现在',
          description: '玩家抵达时，${profile.crisis}已无法继续被掩盖。',
          importance: 10,
          affectedRegions: locations.map((item) => item.id).toList(),
        ),
      ],
      eras: [seed.era, '动荡时代', '当前危机'],
      locations: locations,
      factions: factions,
      factionRelationships: const [
        FactionRelationshipDefinition(
          fromFactionId: 'faction_1',
          toFactionId: 'faction_2',
          type: 'hostile',
          score: -60,
          reason: '争夺关键资源与合法性',
        ),
        FactionRelationshipDefinition(
          fromFactionId: 'faction_2',
          toFactionId: 'faction_3',
          type: 'trade',
          score: 30,
          reason: '交换稀缺资源',
        ),
        FactionRelationshipDefinition(
          fromFactionId: 'faction_3',
          toFactionId: 'faction_1',
          type: 'secret_control',
          score: -20,
          reason: '通过情报与债务暗中施压',
          hidden: true,
        ),
      ],
      npcs: npcs,
      quests: quests,
      items: [
        {
          'id': 'item_archive_key',
          'name': profile.keyItem,
          'category': 'keyItem',
          'description': '能够打开世界核心秘密的关键物品。',
        },
        {
          'id': 'item_field_supply',
          'name': '野外补给包',
          'category': 'consumable',
          'description': '危险区域通用补给。',
        },
      ],
      enemies: [
        EnemyEcologyDefinition(
          id: 'enemy_ecology_1',
          name: profile.enemy,
          regionLocationIds: locations
              .skip(2)
              .take(3)
              .map((item) => item.id)
              .toList(),
          behavior: profile.enemyBehavior,
          population: '受资源与世界事件影响的群落',
          weaknesses: profile.enemyWeaknesses,
          origin: profile.enemyOrigin,
          dangerLevel: 68,
        ),
      ],
      secrets: [
        WorldSecretDefinition(
          id: 'secret_world_truth',
          title: '世界危机的真相',
          content: profile.secret,
          knownByEntityIds: [npcs.last.id],
        ),
        WorldSecretDefinition(
          id: 'secret_identity',
          title: '被篡改的身份',
          content: '${npcs[1].name}的记忆与真实来历并不一致。',
          scope: WorldSecretScope.npc,
          ownerEntityId: npcs[1].id,
        ),
      ],
      startingScenario: StartingScenarioDefinition(
        locationId: locations.first.id,
        npcIds: [npcs.first.id, npcs[1].id],
        conflict: profile.openingConflict,
        playerGoal: '在局势失控前查清第一条线索，并决定信任谁。',
        opening:
            '你抵达${locations.first.name}的第一晚，${profile.openingConflict}。${npcs.first.name}在人群中找到你，希望你立刻介入。',
      ),
      worldRules: [...seed.worldRules, ...seed.specialRules],
      generationNotes: {
        'generator': 'deterministic-fallback',
        'level': seed.level.name,
        'lazyNormalNpcs': true,
      },
    );
  }

  CampaignDocument toCampaignDocument(
    WorldSeed seed,
    WorldBlueprint blueprint,
    WorldGenerationState state,
  ) {
    final now = DateTime.now();
    final difficulty = seed.difficulty.contains('困难')
        ? CampaignDifficulty.hard
        : seed.difficulty.contains('简单')
        ? CampaignDifficulty.easy
        : CampaignDifficulty.normal;
    final openingNode = StoryNode(
      id: 'node_opening',
      title: '开局冲突',
      description: blueprint.startingScenario.conflict,
      effects: [
        {
          'type': 'discoverLocation',
          'locationId': blueprint.startingScenario.locationId,
        },
        if (blueprint.quests.isNotEmpty)
          {'type': 'activateQuest', 'questId': blueprint.quests.first.id},
      ],
      nextNodes: const ['node_open_world'],
    );
    return CampaignDocument(
      id: _uuid.v4(),
      title: blueprint.worldName,
      description: blueprint.summary,
      tags: [seed.genre, seed.theme, ...seed.keywords],
      recommendedPlayers: '1~${seed.playerCount.clamp(1, 8)}',
      estimatedLength: seed.campaignLength,
      ruleSystem: '通用规则',
      theme: seed.theme,
      tone: seed.tone,
      difficulty: difficulty,
      author: 'AI World Generator + 用户',
      source: CampaignSourceType.aiGenerated,
      opening: blueprint.startingScenario.opening,
      systemPrompt:
          '你是 TRPG 世界主持人。世界是可运行的开放系统，不是线性小说。所有地点、NPC、任务与势力必须遵守 WorldBlueprint 和知识边界；玩家可以自由行动。',
      acts: [
        CampaignAct(
          id: 'act_world',
          title: '世界危机',
          description: blueprint.summary,
          chapters: [
            CampaignChapter(
              id: 'chapter_opening',
              title: '进入世界',
              storyNodes: [
                openingNode,
                const StoryNode(
                  id: 'node_open_world',
                  title: '自由探索',
                  description: '玩家可调查地点、势力、NPC 与未解决事件。',
                ),
              ],
            ),
          ],
        ),
      ],
      locations: blueprint.locations
          .map(
            (item) => CampaignLocation(
              id: item.id,
              name: item.name,
              description: item.description,
              discovered: item.id == blueprint.startingScenario.locationId,
              hidden: item.hidden,
              gmNotes: jsonEncode({
                'type': item.type.name,
                'parentLocation': item.parentLocation,
                'connectedLocations': item.connectedLocations,
                'population': item.population,
                'dangerLevel': item.dangerLevel,
                'resources': item.resources,
              }),
            ),
          )
          .toList(),
      npcs: blueprint.npcs
          .map(
            (item) => TRPGNPCProfile(
              npcId: item.id,
              name: item.name,
              description: '${item.age}岁 · ${item.role}',
              personality: item.personality,
              role: item.rank == GeneratedNpcRank.main
                  ? CampaignNpcRole.majorNpc
                  : CampaignNpcRole.npc,
              faction: item.factionId ?? '',
              locationId: item.locationId,
              knownToPlayers: blueprint.startingScenario.npcIds.contains(
                item.id,
              ),
              privateNotes: item.secret,
              metadata: {
                'goal': item.goal,
                'rank': item.rank.name,
                'relationships': item.relationships,
                'worldGenerated': true,
              },
            ),
          )
          .toList(),
      quests: blueprint.quests.map((item) => item.toJson()).toList(),
      items: blueprint.items,
      factions: blueprint.factions.map((item) => item.toJson()).toList(),
      encounters: blueprint.enemies.map((item) => item.toJson()).toList(),
      secrets: blueprint.secrets.map((item) => item.content).toList(),
      endings: blueprint.quests
          .expand((item) => item.branches)
          .map((item) => item['ending']?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(),
      aiGmSettings: {
        'worldGenerator': true,
        'lazyNpcGeneration': true,
        'locationGraph': {
          for (final item in blueprint.locations)
            item.id: item.connectedLocations,
        },
        'factionGraph': blueprint.factionRelationships
            .map((item) => item.toJson())
            .toList(),
      },
      metadata: {
        'worldGeneration': state.toJson(),
        'enemyEcology': blueprint.enemies.map((item) => item.toJson()).toList(),
        'history': blueprint.history.map((item) => item.toJson()).toList(),
      },
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<WorldBlueprint> _generateWithAi({
    required WorldSeed seed,
    required ApiProfile profile,
    required String apiKey,
    void Function(String stage, double progress)? onProgress,
  }) async {
    final ai = _aiService!;
    onProgress?.call('正在生成世界骨架', .08);
    final skeleton = await _jsonCall(
      ai,
      profile,
      apiKey,
      '''根据 WorldSeed 生成可运行 TRPG 世界骨架：${jsonEncode(seed.toJson())}
只返回 JSON 对象，字段：worldName,summary,eras(字符串数组),worldRules(字符串数组),history([{eventId,time,description,importance,affectedRegions}]),startingScenario({locationId,npcIds,conflict,playerGoal,opening})。不要输出小说正文。''',
    );
    onProgress?.call('正在生成地点与地图关系', .24);
    final locations = await _jsonCall(
      ai,
      profile,
      apiKey,
      '''WorldSeed:${jsonEncode(seed.toJson())}\n世界骨架:${jsonEncode(skeleton)}
生成连通地点图。只返回 {"locations":[{"id":"location_1","name":"","description":"","type":"city","parentLocation":null,"connectedLocations":["location_2"],"background":"","population":0,"dangerLevel":0,"resources":[],"tags":[],"hidden":false}]}。
type 只能 region/city/village/dungeon/wilderness/site；禁止孤立地点；开局 locationId 必须存在。''',
    );
    onProgress?.call('正在生成势力与关系', .40);
    final factions = await _jsonCall(
      ai,
      profile,
      apiKey,
      '''世界:${jsonEncode(skeleton)}\n地点:${jsonEncode(locations)}
只返回 {"factions":[{"id":"faction_1","name":"","goal":"","leaderNpcId":"npc_1","territoryLocationIds":["location_1"],"resources":[],"secret":"","tags":[]}],"factionRelationships":[{"fromFactionId":"faction_1","toFactionId":"faction_2","type":"hostile","score":-50,"reason":"","hidden":false}]}。每个势力必须有有效基地；生成竞争、交易或秘密控制关系。''',
    );
    onProgress?.call('正在生成关键 NPC', .56);
    final npcs = await _jsonCall(
      ai,
      profile,
      apiKey,
      '''WorldSeed:${jsonEncode(seed.toJson())}\n地点:${jsonEncode(locations)}\n势力:${jsonEncode(factions)}
只返回 {"npcs":[{"id":"npc_1","name":"","age":30,"role":"","personality":"","goal":"","secret":"","locationId":"location_1","factionId":"faction_1","rank":"main","relationships":{},"tags":[]}]}。
生成 5~10 个 main NPC 和适量 important NPC；rank 只能 main/important/normal；所有引用必须存在。''',
    );
    onProgress?.call('正在生成任务、生态与秘密', .72);
    final content = await _jsonCall(
      ai,
      profile,
      apiKey,
      '''世界:${jsonEncode(skeleton)}\n地点:${jsonEncode(locations)}\n势力:${jsonEncode(factions)}\nNPC:${jsonEncode(npcs)}
只返回 JSON，字段 quests,items,enemies,secrets。
quests 元素字段 id,title,description,giverNpcId,locationId,objectives,rewards,failure,branches(至少3种结局),prerequisiteQuestIds。
enemies 元素字段 id,name,regionLocationIds,behavior,population,weaknesses,origin,dangerLevel。
secrets 元素字段 id,title,content,scope,ownerEntityId,knownByEntityIds,revealed。所有引用必须存在。''',
    );
    return WorldBlueprint.fromJson({
      ...skeleton,
      ...locations,
      ...factions,
      ...npcs,
      ...content,
    });
  }

  Future<Map<String, Object?>> _jsonCall(
    AiService ai,
    ApiProfile profile,
    String apiKey,
    String prompt,
  ) async {
    String raw = '';
    for (var attempt = 0; attempt < 3; attempt++) {
      raw = '';
      final request = attempt == 0
          ? prompt
          : '修复并完整重新输出下面任务要求的 JSON。只输出一个 JSON 对象，不要解释、思考过程或代码围栏。\n$prompt';
      await for (final chunk in ai.streamChat(
        profile: profile.copyWith(maxTokens: 8000),
        apiKey: apiKey,
        messages: [
          {
            'role': 'system',
            'content':
                '你是 TRPG 世界设计师，运行在严格 JSON harness 中。不要生成单纯故事；生成可以被程序运行的开放世界。所有地点、NPC、任务、势力必须互相连接。只输出一个合法 JSON 对象。',
          },
          {'role': 'user', 'content': request},
        ],
      )) {
        raw += chunk;
      }
      try {
        return AICampaignGenerator.decodeJsonObject(raw);
      } on FormatException {
        if (attempt == 2) rethrow;
      }
    }
    throw const FormatException('AI 没有返回可用世界 JSON');
  }

  _LocalWorldTheme _localTheme(WorldSeed seed) {
    final text = '${seed.theme}${seed.genre}${seed.keywords.join()}';
    if (text.contains('武侠') || text.contains('江湖')) {
      return const _LocalWorldTheme.wuxia();
    }
    if (text.contains('末世') || text.contains('废土')) {
      return const _LocalWorldTheme.apocalypse();
    }
    if (text.contains('西幻') || text.contains('奇幻') || text.contains('魔法')) {
      return const _LocalWorldTheme.fantasy();
    }
    return const _LocalWorldTheme.generic();
  }
}

class WorldGenerationRuntime {
  const WorldGenerationRuntime();

  TRPGSession initializeSession(
    TRPGSession session,
    CampaignDocument campaign,
  ) {
    final raw = campaign.metadata['worldGeneration'];
    if (raw is! Map) return session;
    final generation = WorldGenerationState.fromJson(
      raw.cast<String, Object?>(),
    );
    final blueprint = generation.blueprint;
    if (blueprint == null || blueprint.locations.isEmpty) return session;
    final start = blueprint.startingScenario;
    final location = blueprint.locations.firstWhere(
      (item) => item.id == start.locationId,
      orElse: () => blueprint.locations.first,
    );
    final quests = blueprint.quests
        .map(
          (item) => QuestState(
            questId: item.id,
            title: item.title,
            description: item.description,
            objectives: item.objectives
                .asMap()
                .entries
                .map(
                  (entry) => QuestObjective(
                    id: '${item.id}_objective_${entry.key + 1}',
                    description: entry.value,
                  ),
                )
                .toList(),
            status: item == blueprint.quests.first
                ? QuestStatus.active
                : QuestStatus.discovered,
            discoveredAt: session.createdAt,
          ),
        )
        .toList();
    final npcStates = blueprint.npcs
        .map(
          (item) => NPCState(
            npcId: item.id,
            name: item.name,
            locationId: item.locationId,
            knownToPlayer: start.npcIds.contains(item.id),
            notes: jsonEncode({
              'factionId': item.factionId,
              'rank': item.rank.name,
              'worldGenerated': true,
            }),
          ),
        )
        .toList();
    final next = session.copyWith(
      currentScene: start.opening,
      campaignState: session.campaignState.copyWith(
        currentLocationId: location.id,
        activeQuests: blueprint.quests.isEmpty
            ? const []
            : [blueprint.quests.first.id],
        discoveredLocations: [location.id],
        quests: quests,
        variables: {
          ...session.campaignState.variables,
          'worldGenerationId': generation.generationId,
        },
      ),
      worldState: session.worldState.copyWith(
        time: '开局',
        location: location.name,
        knownNpcs: start.npcIds,
        factionRelations: {
          for (final relation in blueprint.factionRelationships)
            '${relation.fromFactionId}:${relation.toFactionId}': relation.score,
        },
        customVariables: {
          ...session.worldState.customVariables,
          'worldName': blueprint.worldName,
          'locationGraph': {
            for (final item in blueprint.locations)
              item.id: item.connectedLocations,
          },
          'enemyEcology': blueprint.enemies
              .map((item) => item.toJson())
              .toList(),
        },
        currentScene: SceneState(
          sceneId: 'world_start',
          locationId: location.id,
          title: location.name,
          description: location.description,
          atmosphere: start.conflict,
          npcIds: start.npcIds,
          tags: [location.type.name, ...location.tags],
        ),
        npcs: npcStates,
      ),
      npcLocations: {
        for (final npc in blueprint.npcs)
          npc.id: CharacterLocationState(
            characterId: npc.id,
            sceneId: npc.locationId == location.id ? 'world_start' : '',
            locationId: npc.locationId,
            enteredAt: session.createdAt,
          ),
      },
      gmState: GMState.fromJson({
        ...session.gmState.toJson(),
        'privateNotes': [
          session.gmState.privateNotes,
          ...blueprint.secrets.map((item) => '${item.title}: ${item.content}'),
        ].where((item) => item.trim().isNotEmpty).join('\n'),
        'plotHooks': blueprint.quests.map((item) => item.title).toList(),
        'futureEvents': blueprint.history
            .where((item) => item.time == '现在')
            .map((item) => item.description)
            .toList(),
      }),
      worldGenerationState: generation.copyWith(lockedAfterPlay: true),
    );
    final withLivingNpcs = const LivingNPCService().ensureInitialized(next);
    return const FactionManager().ensureInitialized(withLivingNpcs);
  }

  TRPGSession enterLocation(TRPGSession session, String locationId) {
    final generation = session.worldGenerationState;
    final blueprint = generation.blueprint;
    if (blueprint == null ||
        !blueprint.locations.any((item) => item.id == locationId)) {
      throw ArgumentError.value(locationId, 'locationId', '地点不存在');
    }
    if (generation.generatedLocationIds.contains(locationId)) return session;
    final location = blueprint.locations.firstWhere(
      (item) => item.id == locationId,
    );
    final ordinal = generation.generatedLocationIds.length + 1;
    final lazyNpcs = List.generate(
      2,
      (index) => GeneratedNpcDefinition(
        id: 'lazy_${locationId}_${ordinal}_$index',
        name: '${location.name}${index == 0 ? '居民' : '行商'}${ordinal + index}',
        age: 24 + ordinal + index * 7,
        role: index == 0 ? '当地居民' : '流动商人',
        personality: index == 0 ? '熟悉本地、谨慎' : '健谈、重视利益',
        goal: '在${location.name}维持自己的生活与关系',
        locationId: locationId,
        rank: GeneratedNpcRank.normal,
        tags: const ['lazy_generated'],
      ),
    );
    final expanded = blueprint.copyWith(npcs: [...blueprint.npcs, ...lazyNpcs]);
    var next = session.copyWith(
      worldState: session.worldState.copyWith(
        npcs: [
          ...session.worldState.npcs,
          ...lazyNpcs.map(
            (npc) => NPCState(
              npcId: npc.id,
              name: npc.name,
              locationId: locationId,
              notes: jsonEncode({
                'worldGenerated': true,
                'lazyGenerated': true,
              }),
            ),
          ),
        ],
      ),
      npcLocations: {
        ...session.npcLocations,
        for (final npc in lazyNpcs)
          npc.id: CharacterLocationState(
            characterId: npc.id,
            locationId: locationId,
            enteredAt: DateTime.now(),
          ),
      },
      worldGenerationState: generation.copyWith(
        blueprint: expanded,
        generatedLocationIds: [...generation.generatedLocationIds, locationId],
        generatedData: {
          ...generation.generatedData,
          'lastLazyGenerationAt': DateTime.now().toIso8601String(),
        },
      ),
    );
    next = const LivingNPCService().ensureInitialized(next);
    return const FactionManager().ensureInitialized(next);
  }

  WorldGenerationState fork(WorldGenerationState source, WorldBlueprint next) {
    if (!source.isGenerated) throw StateError('没有可 Fork 的已生成世界');
    return WorldGenerationState(
      seed: source.seed,
      blueprint: next,
      generatedData: {
        'forkedAt': DateTime.now().toIso8601String(),
        'sourceVersion': source.generationVersion,
      },
      generationVersion: source.generationVersion + 1,
      generationId: const Uuid().v4(),
      parentGenerationId: source.generationId,
      generatedLocationIds: [next.startingScenario.locationId],
    );
  }
}

class _LocalWorldTheme {
  const _LocalWorldTheme({
    required this.worldName,
    required this.locations,
    required this.npcs,
    required this.roles,
    required this.factions,
    required this.factionGoals,
    required this.resources,
    required this.quests,
    required this.crisis,
    required this.oldHistory,
    required this.recentHistory,
    required this.keyItem,
    required this.enemy,
    required this.enemyBehavior,
    required this.enemyWeaknesses,
    required this.enemyOrigin,
    required this.secret,
    required this.openingConflict,
  });

  const _LocalWorldTheme.fantasy()
    : this(
        worldName: '裂冠群国',
        locations: const [
          '晨星城',
          '灰烬修道院',
          '翡翠村',
          '沉没王陵',
          '北境隘口',
          '镜湖塔',
          '龙骨荒原',
          '月影矿坑',
          '王庭废墟',
          '旧神庭院',
        ],
        npcs: const [
          '艾琳',
          '罗德里克',
          '米蕾娅',
          '塔恩',
          '塞拉',
          '奥斯温',
          '芙蕾',
          '加尔',
          '伊莎',
          '诺兰',
        ],
        roles: const ['宫廷使者', '边境骑士', '异端学者', '游侠', '商会代表'],
        factions: const ['晨星王庭', '翠叶盟约', '灰烬秘会'],
        factionGoals: const ['重建王权并终止战乱', '保护古老森林与边境村落', '唤醒被封印的魔法知识'],
        resources: const ['秘银', '魔药', '古代卷轴'],
        quests: const ['失落王冠', '沉默的村庄', '王陵之门', '破碎盟约', '龙骨下的名字'],
        crisis: '失落王冠重新现世',
        oldHistory: '旧王朝在魔法灾变中覆灭，王冠与继承谱系一同失踪。',
        recentHistory: '三个势力在废墟上建立脆弱秩序，彼此都宣称拥有合法性。',
        keyItem: '星银王冠碎片',
        enemy: '灰烬兽群',
        enemyBehavior: '在魔力潮汐升高时成群迁徙并袭击聚落',
        enemyWeaknesses: const ['星银', '净化法阵'],
        enemyOrigin: '旧王朝魔法灾变留下的变异生态',
        secret: '王冠并非权力象征，而是压制地下魔力裂隙的封印。',
        openingConflict: '城内所有魔法灯同时熄灭，一名王庭档案员失踪',
      );

  const _LocalWorldTheme.apocalypse()
    : this(
        worldName: '余烬穹顶',
        locations: const [
          '穹顶避难所',
          '废弃医院',
          '地下实验室',
          '盐尘车站',
          '黑塔市场',
          '辐射沼泽',
          '旧城数据中心',
          '裂谷农场',
          '无人机坟场',
          '零号反应堆',
        ],
        npcs: const [
          '岚',
          '顾衡',
          '伊芙',
          '老钟',
          '白鸦',
          '米娅',
          '洛克',
          '祁安',
          '赫克托',
          '小满',
        ],
        roles: const ['避难所工程师', '废土向导', '数据猎人', '医疗官', '巡逻队长'],
        factions: const ['方舟联盟', '拾荒者公社', '静默核心'],
        factionGoals: const ['恢复旧文明基础设施', '保障废土居民自由生存', '收集并控制灾前人工智能'],
        resources: const ['净水芯片', '能源电池', '旧文明数据'],
        quests: const ['熄灭的穹顶', '医院的求救信号', '最后一班列车', '被删除的居民', '反应堆之下'],
        crisis: '地下城市能源系统正在被未知智能接管',
        oldHistory: '旧文明在自主战争网络失控后崩溃，地表生态被长期污染。',
        recentHistory: '幸存者建立地下穹顶，却逐渐遗忘建造者留下的真实限制。',
        keyItem: '管理员根密钥',
        enemy: '自律清扫集群',
        enemyBehavior: '按照灾前错误指令识别并清除未经登记的生命',
        enemyWeaknesses: const ['电磁脉冲', '管理员认证'],
        enemyOrigin: '旧文明城市维护 AI 的失控子程序',
        secret: '地表已经局部恢复，而穹顶管理者一直伪造污染数据以维持控制。',
        openingConflict: '避难所主电网突然断电，一名维护员在封锁层失踪',
      );

  const _LocalWorldTheme.wuxia()
    : this(
        worldName: '山河残卷',
        locations: const [
          '临江府',
          '青竹镇',
          '断剑山庄',
          '藏经地宫',
          '雁回关',
          '听雨楼',
          '无名渡',
          '药王谷',
          '天机台',
          '皇陵古道',
        ],
        npcs: const [
          '沈雁归',
          '柳如烟',
          '顾长风',
          '苏晚晴',
          '唐无咎',
          '燕七',
          '谢听澜',
          '陆青崖',
          '白蘅',
          '霍云生',
        ],
        roles: const ['江湖游侠', '门派执事', '密探', '医者', '镖局掌柜'],
        factions: const ['武林盟', '听雨楼', '无相教'],
        factionGoals: const ['维持门派秩序并寻找盟主', '掌握天下情报换取生存空间', '颠覆旧门派并夺取残卷'],
        resources: const ['内功心法', '药材', '密报'],
        quests: const ['失踪的盟主', '青竹镇血案', '断剑重铸', '雨夜密令', '山河残卷'],
        crisis: '失传的山河残卷再次现身江湖',
        oldHistory: '前朝末年，武林各派共同封存了一部足以改变天下格局的残卷。',
        recentHistory: '盟主离奇失踪，各派以追查为名重启旧日争斗。',
        keyItem: '山河残卷拓本',
        enemy: '无相死士',
        enemyBehavior: '以小队潜伏、刺探并在目标孤立时发动袭击',
        enemyWeaknesses: const ['破除易容', '截断暗号联络'],
        enemyOrigin: '无相教长期训练的隐秘行动者',
        secret: '所谓残卷不是绝世武功，而是一份记录各派与朝廷旧债的名册。',
        openingConflict: '临江府的武林大会尚未开场，盟主信物却出现在一具无名尸体旁',
      );

  const _LocalWorldTheme.generic()
    : this(
        worldName: '交界之城',
        locations: const [
          '中央城',
          '旧工业区',
          '河岸社区',
          '封锁研究站',
          '北部关卡',
          '档案馆',
          '地下通道',
          '远郊农场',
          '废弃车站',
          '核心禁区',
        ],
        npcs: const [
          '林澈',
          '安娜',
          '周岚',
          '凯尔',
          '米拉',
          '韩舟',
          '伊森',
          '苏菲',
          '诺亚',
          '叶宁',
        ],
        roles: const ['调查员', '技术人员', '社区代表', '商人', '守卫'],
        factions: const ['城市议会', '自由联合会', '观测局'],
        factionGoals: const ['维持城市秩序', '保护居民自治', '控制异常现象'],
        resources: const ['情报', '通行证', '稀缺设备'],
        quests: const ['消失的档案', '封锁线之外', '无名来客', '暗处交易', '核心真相'],
        crisis: '一场被掩盖的异常事件重新出现',
        oldHistory: '城市建立在一处被人为抹去历史的遗址上。',
        recentHistory: '多个组织开始争夺同一批失落档案。',
        keyItem: '核心区通行证',
        enemy: '异常追猎者',
        enemyBehavior: '追踪接触过核心秘密的人',
        enemyWeaknesses: const ['强光', '切断追踪信号'],
        enemyOrigin: '旧事件留下的失控防御机制',
        secret: '城市的安全建立在周期性牺牲边缘区域之上。',
        openingConflict: '全城警报短暂响起后被官方否认，一名知情者失踪',
      );

  final String worldName;
  final List<String> locations;
  final List<String> npcs;
  final List<String> roles;
  final List<String> factions;
  final List<String> factionGoals;
  final List<String> resources;
  final List<String> quests;
  final String crisis;
  final String oldHistory;
  final String recentHistory;
  final String keyItem;
  final String enemy;
  final String enemyBehavior;
  final List<String> enemyWeaknesses;
  final String enemyOrigin;
  final String secret;
  final String openingConflict;
}
