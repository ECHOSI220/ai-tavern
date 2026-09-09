import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/campaign_models.dart';
import '../../models/trpg_models.dart';
import '../../services/trpg/trpg_recap_service.dart';

enum TrpgPanelType { clues, map, people, timeline, recap, gm }

class TrpgImmersionPanel extends StatelessWidget {
  const TrpgImmersionPanel({
    required this.session,
    required this.type,
    this.playerId,
    this.isGm = false,
    this.onSessionChanged,
    super.key,
  });
  final TRPGSession session;
  final TrpgPanelType type;
  final String? playerId;
  final bool isGm;
  final ValueChanged<TRPGSession>? onSessionChanged;

  CampaignDocument? get _campaign {
    final raw = session.immersionState.campaignSnapshot;
    return raw.isEmpty ? null : CampaignDocument.fromJson(raw);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_title)),
    body: switch (type) {
      TrpgPanelType.clues => _clues(context),
      TrpgPanelType.map => _map(context),
      TrpgPanelType.people => _people(context),
      TrpgPanelType.timeline => _timeline(context),
      TrpgPanelType.recap => _recap(context),
      TrpgPanelType.gm => _gm(context),
    },
  );

  String get _title => switch (type) {
    TrpgPanelType.clues => '线索板',
    TrpgPanelType.map => '场景地图',
    TrpgPanelType.people => '人物',
    TrpgPanelType.timeline => '事件日志',
    TrpgPanelType.recap => '冒险回顾',
    TrpgPanelType.gm => 'GM Panel',
  };

  bool _visible(InformationVisibility visibility, List<String> owners) =>
      isGm ||
      visibility == InformationVisibility.public ||
      (playerId != null && owners.contains(playerId));

  Widget _clues(BuildContext context) {
    final campaign = _campaign;
    final clues =
        campaign?.clues
            .where(
              (clue) =>
                  clue.discovered &&
                  _visible(clue.visibility, clue.ownerPlayerIds),
            )
            .toList() ??
        const <CampaignClue>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.hub_outlined),
            title: Text('稳定布局线索板'),
            subtitle: Text('按线索、NPC、地点和任务显示关联；第一版不使用自由拖拽。'),
          ),
        ),
        if (clues.isEmpty) const ListTile(title: Text('尚未发现可见线索')),
        ...clues.map(
          (clue) => Card(
            child: ExpansionTile(
              leading: Icon(
                clue.visibility == InformationVisibility.public
                    ? Icons.search
                    : Icons.lock_outline,
              ),
              title: Text(clue.name),
              subtitle: Text(clue.source),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(clue.description),
                ),
                const SizedBox(height: 8),
                ...clue.relations.map(
                  (relation) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.link),
                    title: Text(
                      '${relation.entityType} · ${relation.entityId}',
                    ),
                  ),
                ),
                if (clue.visibility != InformationVisibility.public &&
                    onSessionChanged != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _publishClue(clue),
                      icon: const Icon(Icons.campaign_outlined),
                      label: const Text('公开线索'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _publishClue(CampaignClue clue) {
    final campaign = _campaign;
    if (campaign == null) return;
    final updatedClues = campaign.clues
        .map(
          (value) => value.id == clue.id
              ? CampaignClue.fromJson({
                  ...value.toJson(),
                  'visibility': InformationVisibility.public.name,
                  'ownerPlayerIds': const <String>[],
                })
              : value,
        )
        .toList();
    final updatedCampaign = campaign.copyWith(clues: updatedClues);
    onSessionChanged?.call(
      session.copyWith(
        immersionState: session.immersionState.copyWith(
          campaignSnapshot: updatedCampaign.toJson(),
          privateKnowledge: session.immersionState.privateKnowledge
              .map(
                (value) => value.id == clue.id
                    ? value.copyWith(
                        visibility: InformationVisibility.public,
                        ownerPlayerIds: const [],
                        revealed: true,
                      )
                    : value,
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _people(BuildContext context) {
    final campaign = _campaign;
    final profiles =
        campaign?.npcs.where(
          (npc) =>
              isGm ||
              npc.knownToPlayers ||
              session.immersionState.discoveredNpcIds.contains(npc.npcId),
        ) ??
        const <TRPGNPCProfile>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: profiles.map((npc) {
        final state = session.immersionState.npcInstances
            .where((value) => value.npcId == npc.npcId)
            .firstOrNull;
        final relation = state?.relationship ?? npc.relationship;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage:
                  npc.avatar != null && File(npc.avatar!).existsSync()
                  ? FileImage(File(npc.avatar!))
                  : null,
              child: npc.avatar == null ? const Icon(Icons.person) : null,
            ),
            title: Text(npc.name),
            subtitle: Text(
              '${npc.role.name} · ${_relationLabel(relation)}\n${npc.description}',
            ),
            isThreeLine: true,
          ),
        );
      }).toList(),
    );
  }

  String _relationLabel(int value) {
    if (value <= -60) return '敌视';
    if (value <= -20) return '冷淡';
    if (value < 20) return '中立';
    if (value < 60) return '友好';
    return '信任';
  }

  Widget _map(BuildContext context) {
    final campaign = _campaign;
    final location =
        campaign?.locations
            .where(
              (value) => value.id == session.campaignState.currentLocationId,
            )
            .firstOrNull ??
        campaign?.locations.firstOrNull;
    if (location == null) return const Center(child: Text('当前剧本没有场景地图'));
    final visibleMarkers = location.markers.where(
      (marker) =>
          isGm ||
          (marker.discovered &&
              marker.visibility == InformationVisibility.public) ||
          session.immersionState.revealedMarkerIds.contains(marker.id),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              location.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(location.description),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 16 / 10,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Positioned.fill(
                      child:
                          location.mapImage != null &&
                              File(location.mapImage!).existsSync()
                          ? Image.file(
                              File(location.mapImage!),
                              fit: BoxFit.cover,
                            )
                          : ColoredBox(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHigh,
                              child: const Center(
                                child: Icon(Icons.map_outlined, size: 84),
                              ),
                            ),
                    ),
                    ...visibleMarkers.map(
                      (marker) => Positioned(
                        left:
                            (constraints.maxWidth - 40) * marker.x.clamp(0, 1),
                        top:
                            (constraints.maxHeight - 40) * marker.y.clamp(0, 1),
                        child: Tooltip(
                          message: marker.label,
                          child: CircleAvatar(
                            radius: 20,
                            child: Icon(_markerIcon(marker.type), size: 20),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _markerIcon(String type) => switch (type) {
    'player' => Icons.person_pin_circle,
    'npc' => Icons.person,
    'clue' => Icons.search,
    'danger' => Icons.warning_amber,
    'object' => Icons.category_outlined,
    _ => Icons.place,
  };

  Widget _timeline(BuildContext context) {
    final entries = session.immersionState.timeline.where(
      (entry) => _visible(entry.visibility, entry.ownerPlayerIds),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: entries.isEmpty
          ? session.eventLog.reversed
                .map(
                  (event) => ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(event.type.name),
                    subtitle: Text(
                      event.timestamp.toLocal().toString().substring(0, 16),
                    ),
                  ),
                )
                .toList()
          : entries
                .toList()
                .reversed
                .map(
                  (entry) => ListTile(
                    leading: Icon(
                      entry.visibility == InformationVisibility.public
                          ? Icons.history
                          : Icons.lock_outline,
                    ),
                    title: Text(entry.title),
                    subtitle: Text(
                      '${entry.createdAt.toLocal().toString().substring(0, 16)}\n${entry.detail}',
                    ),
                    isThreeLine: entry.detail.isNotEmpty,
                  ),
                )
                .toList(),
    );
  }

  Widget _recap(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: SelectableText(
      const TRPGRecapService().buildStructuredRecap(
        session,
        playerId: playerId,
      ),
      style: Theme.of(context).textTheme.bodyLarge,
    ),
  );

  Widget _gm(BuildContext context) {
    if (!isGm) {
      return const Center(
        child: Text('只有真人 GM / 房主授权的 GM 可以进入。API Host Provider 不等于 GM。'),
      );
    }
    final campaign = _campaign;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section(
          context,
          '隐藏 NPC',
          campaign?.npcs
                  .where((value) => !value.knownToPlayers)
                  .map((value) => value.name) ??
              const [],
        ),
        _section(
          context,
          '未发现线索',
          campaign?.clues
                  .where((value) => !value.discovered)
                  .map((value) => value.name) ??
              const [],
        ),
        _section(
          context,
          '秘密地点',
          campaign?.locations
                  .where((value) => value.hidden)
                  .map((value) => value.name) ??
              const [],
        ),
        _section(context, '未来事件', session.gmState.futureEvents),
        _section(context, 'GM Secrets', campaign?.secrets ?? const []),
        _section(
          context,
          '私人玩家行动',
          session.immersionState.timeline
              .where(
                (value) => value.visibility != InformationVisibility.public,
              )
              .map((value) => '${value.title}：${value.detail}'),
        ),
      ],
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    Iterable<String> values,
  ) => Card(
    child: ExpansionTile(
      title: Text(title),
      children: values.isEmpty
          ? [const ListTile(title: Text('暂无'))]
          : values.map((value) => ListTile(title: Text(value))).toList(),
    ),
  );
}
