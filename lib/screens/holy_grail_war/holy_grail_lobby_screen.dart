import '../../app/skins/skin_icon.dart';
import 'package:flutter/material.dart';
import '../../app/skins/character_theme.dart';
import '../../app/skins/theme_craft.dart';

import '../../models/holy_grail_war_models.dart';
import '../../models/trpg_models.dart';
import '../../repositories/trpg_session_repository.dart';
import '../../services/trpg/holy_grail_war_manager.dart';

class HolyGrailLobbyScreen extends StatefulWidget {
  const HolyGrailLobbyScreen({
    required this.session,
    required this.repository,
    super.key,
  });

  final TRPGSession session;
  final TRPGSessionRepository repository;

  @override
  State<HolyGrailLobbyScreen> createState() => _HolyGrailLobbyScreenState();
}

class _HolyGrailLobbyScreenState extends State<HolyGrailLobbyScreen> {
  static const _manager = HolyGrailWarManager();
  late TRPGSession _session = _manager.prepareOpening(widget.session);
  final MasterArchetype _archetype = MasterArchetype.ordinaryMage;
  final _wish = TextEditingController();
  final _catalyst = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.session.metadata['holyGrailOpeningPrepared'] != true) {
      Future<void>.microtask(() => widget.repository.upsert(_session));
    }
  }

  String get _playerId => _session.players.first.playerId;
  MasterCharacter? get _master => _session.holyGrailState.masters
      .where((value) => value.ownerPlayerId == _playerId)
      .firstOrNull;
  ServantCharacter? get _servant {
    final id = _master?.servantId;
    return _session.holyGrailState.servants
        .where((value) => value.servantId == id)
        .firstOrNull;
  }

  @override
  void dispose() {
    _wish.dispose();
    _catalyst.dispose();
    super.dispose();
  }

  Future<void> _save(TRPGSession session) async {
    await widget.repository.upsert(session);
    if (mounted) setState(() => _session = session);
  }

  Future<void> _select() async {
    setState(() => _busy = true);
    final result = _manager.selectMaster(
      _session,
      playerId: _playerId,
      archetype: _archetype,
      wish: _wish.text,
    );
    if (result.succeeded) await _save(result.session);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.summary)));
    }
  }

  Future<void> _summon() async {
    if (_master == null) await _select();
    final master = _master;
    if (master == null || !mounted) return;
    setState(() => _busy = true);
    final result = _manager.summonServant(
      _session,
      masterId: master.masterId,
      catalyst: _catalyst.text,
    );
    if (result.succeeded) await _save(result.session);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.summary)));
    }
  }

  Future<void> _rerollMaster() async {
    setState(() => _busy = true);
    final result = _manager.rerollMasterDossier(
      _session,
      playerId: _playerId,
      nonce: DateTime.now().microsecondsSinceEpoch,
    );
    if (result.succeeded) await _save(result.session);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.summary)));
  }

  @override
  Widget build(BuildContext context) {
    final state = _session.holyGrailState.forPlayer(_playerId);
    final servant = _servant;
    final master = _master;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('圣杯战争 Lobby'),
            Text('选择御主 · 召唤从者 · 情报隔离', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '第七次圣杯战争：冬木残响',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '当前阶段：${HolyGrailWarManager.holyGrailPhaseLabel(state.phase)} · 存活阵营 ${state.masters.where((value) => value.alive).length}/7',
                      ),
                      const SizedBox(height: 6),
                      const Text('其他御主的位置、计划、从者真名和宝具不会发送到你的客户端，必须通过调查获得。'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '1. 你的私密御主档案',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (master == null) ...[
                const Text('尚未生成御主档案。'),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _select,
                  icon: const SkinIcon(Icons.casino_outlined),
                  label: const Text('掷骰生成命运'),
                ),
              ] else ...[
                _MasterDossierCard(master: master),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _rerollMaster,
                  icon: const SkinIcon(Icons.casino_outlined),
                  label: Text(
                    '随机重抽御主档案（已重抽 ${master.resources['dossierRerollCount'] ?? 0} 次）',
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '只更换你的卷入事件、家系、起源、性格与能力骰；不会公开资料，也不会改变其他阵营或已签订的英灵契约。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Text(
                '2. 你的私密英灵契约',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (servant == null) ...[
                TextField(
                  controller: _catalyst,
                  decoration: const InputDecoration(
                    labelText: '召唤媒介（可留空）',
                    hintText: '古剑碎片、染血的箭头、王冠残片……',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy || master == null ? null : _summon,
                  icon: const SkinIcon(Icons.auto_awesome),
                  label: const Text('启动召唤仪式'),
                ),
              ] else
                _ServantCard(servant: servant, master: master!),
              const SizedBox(height: 22),
              Text('战争状态', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const SkinIcon(Icons.change_circle_outlined),
                  title: Text('令咒 ${master?.commandSpells ?? 0}/3'),
                  subtitle: const Text('可用于强制命令、强化能力或召回从者；强制命令会影响关系。'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const SkinIcon(Icons.manage_search),
                  title: const Text('情报记录'),
                  subtitle: Text(
                    '已知从者 ${state.informationByPlayer[_playerId]?.knownServantIds.length ?? 0} · '
                    '身份推测 ${state.informationByPlayer[_playerId]?.suspectedIdentity.length ?? 0}',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: servant == null
                    ? null
                    : () => Navigator.pop(context, _session),
                icon: const SkinIcon(Icons.play_arrow),
                label: const Text('进入圣杯战争'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServantCard extends StatelessWidget {
  const _ServantCard({required this.servant, required this.master});
  final ServantCharacter servant;
  final MasterCharacter master;

  @override
  Widget build(BuildContext context) => Card(
    color: CharacterThemeExtension.of(context)?.wine,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                child: Text(
                  HolyGrailWarManager.holyGrailClassLabel(
                    servant.classType,
                  ).substring(0, 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  HolyGrailWarManager.holyGrailClassLabel(servant.classType),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const Chip(label: Text('契约成立')),
            ],
          ),
          const SizedBox(height: 12),
          Text(servant.appearance),
          const SizedBox(height: 8),
          Text('真名：${servant.trueName}（仅你可见）'),
          Text('宝具：${servant.noblePhantasm.hiddenName}'),
          Text('人格：${servant.personality}'),
          Text(
            '参数：筋力 ${HolyGrailWarManager.parameterRankLabel(servant.parameters.strength)} / '
            '耐久 ${HolyGrailWarManager.parameterRankLabel(servant.parameters.endurance)} / '
            '敏捷 ${HolyGrailWarManager.parameterRankLabel(servant.parameters.agility)} / '
            '魔力 ${HolyGrailWarManager.parameterRankLabel(servant.parameters.mana)} / '
            '幸运 ${HolyGrailWarManager.parameterRankLabel(servant.parameters.luck)} / '
            '宝具 ${HolyGrailWarManager.parameterRankLabel(servant.parameters.noblePhantasm)}',
          ),
          Text('技能：${servant.skills.join('、')}'),
          const SizedBox(height: 8),
          Text('御主：${master.name} · 令咒 ${master.commandSpells}/3'),
        ],
      ),
    ),
  );
}

class _MasterDossierCard extends StatelessWidget {
  const _MasterDossierCard({required this.master});

  final MasterCharacter master;

  @override
  Widget build(BuildContext context) {
    final attributes = master.resources['attributes'] is Map
        ? (master.resources['attributes'] as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, Object?>{};
    final rolls = master.resources['attributeRolls'] is Map
        ? (master.resources['attributeRolls'] as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, Object?>{};
    String stat(String key, String label) =>
        '$label ${attributes[key] ?? '?'}（${(rolls[key] as List? ?? const []).join('+')}）';
    return Card(
      color: CharacterThemeExtension.of(context)?.wine,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (CharacterThemeExtension.of(context) != null)
              const Align(
                alignment: Alignment.centerRight,
                child: CraftEmblem(size: 32),
              ),
            const Chip(
              avatar: SkinIcon(Icons.lock_outline, size: 16),
              label: Text('仅你与 GM 可见'),
            ),
            const SizedBox(height: 8),
            Text(
              master.resources['incitingIncident']?.toString() ?? '',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Text(
              '${HolyGrailWarManager.masterArchetypeLabel(master.archetype)} · ${master.family} · 起源“${master.origin}”',
            ),
            Text('愿望：${master.wish}'),
            const SizedBox(height: 8),
            Text('${stat('strength', '体魄')}　${stat('agility', '敏捷')}'),
            Text('${stat('endurance', '耐力')}　${stat('magecraft', '魔术')}'),
            Text('${stat('perception', '感知')}　${stat('willpower', '意志')}'),
            Text('魔术资质 ${master.magicAbility} · 令咒 ${master.commandSpells}/3'),
          ],
        ),
      ),
    );
  }
}
