import '../../app/skins/skin_icon.dart';
import '../../app/skins/character_theme.dart';
import 'package:flutter/material.dart';

import '../../models/trpg_models.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/campaign_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/trpg_session_repository.dart';
import '../../services/ai_service.dart';
import 'solo_session_screen.dart';
import 'solo_setup_screen.dart';
import '../campaigns/campaign_library_screen.dart';
import '../holy_grail_war/holy_grail_lobby_screen.dart';
import '../rule_library/rule_library_screen.dart';
import '../../services/trpg/campaign_template_service.dart';

class SoloTrpgHomeScreen extends StatefulWidget {
  const SoloTrpgHomeScreen({
    required this.repository,
    required this.campaignRepository,
    required this.characterRepository,
    required this.apiRepository,
    required this.settingsRepository,
    required this.aiService,
    required this.onExitToModes,
    super.key,
  });

  final TRPGSessionRepository repository;
  final CampaignRepository campaignRepository;
  final CharacterCardRepository characterRepository;
  final ApiRepository apiRepository;
  final SettingsRepository settingsRepository;
  final AiService aiService;
  final VoidCallback onExitToModes;

  @override
  State<SoloTrpgHomeScreen> createState() => _SoloTrpgHomeScreenState();
}

class _SoloTrpgHomeScreenState extends State<SoloTrpgHomeScreen> {
  List<TRPGSession> _sessions = const [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await widget.repository.getAll(mode: TRPGMode.solo);
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final session = await Navigator.push<TRPGSession>(
      context,
      MaterialPageRoute(
        builder: (_) => SoloSetupScreen(
          repository: widget.repository,
          apiRepository: widget.apiRepository,
          settingsRepository: widget.settingsRepository,
          aiService: widget.aiService,
          characterRepository: widget.characterRepository,
          campaignRepository: widget.campaignRepository,
        ),
      ),
    );
    if (session != null && mounted) await _open(session);
    await _load();
  }

  Future<void> _createHolyGrail() async {
    final template = const CampaignTemplateService().holyGrailWar();
    await widget.campaignRepository.upsert(template);
    if (!mounted) return;
    final created = await Navigator.push<TRPGSession>(
      context,
      MaterialPageRoute(
        builder: (_) => SoloSetupScreen(
          repository: widget.repository,
          apiRepository: widget.apiRepository,
          settingsRepository: widget.settingsRepository,
          aiService: widget.aiService,
          characterRepository: widget.characterRepository,
          campaignRepository: widget.campaignRepository,
          initialCampaign: template,
        ),
      ),
    );
    if (created == null || !mounted) return;
    final ready = await Navigator.push<TRPGSession>(
      context,
      MaterialPageRoute(
        builder: (_) => HolyGrailLobbyScreen(
          session: created,
          repository: widget.repository,
        ),
      ),
    );
    if (ready != null && mounted) await _open(ready);
    await _load();
  }

  Future<void> _open(TRPGSession session) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SoloSessionScreen(
          session: session,
          repository: widget.repository,
          apiRepository: widget.apiRepository,
          settingsRepository: widget.settingsRepository,
          aiService: widget.aiService,
        ),
      ),
    );
    await _load();
  }

  Future<void> _delete(TRPGSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除跑团存档？'),
        content: Text('“${session.title}”的冒险进度将被删除。'),
        actions: [
          IconButton(
            tooltip: '圣杯战争',
            icon: const SkinIcon(Icons.auto_awesome),
            onPressed: _createHolyGrail,
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.repository.delete(session.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onExitToModes,
          icon: const SkinIcon(Icons.home_outlined),
          tooltip: '模式主页',
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('单人跑团'),
            Text('AI 主持 · 单人冒险', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '规则资料库',
            icon: const SkinIcon(Icons.menu_book_outlined),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const RuleLibraryScreen()),
            ),
          ),
          IconButton(
            tooltip: '剧本库',
            icon: const SkinIcon(Icons.auto_stories_outlined),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => CampaignLibraryScreen(
                  repository: widget.campaignRepository,
                  characterRepository: widget.characterRepository,
                  apiRepository: widget.apiRepository,
                  aiService: widget.aiService,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: ThemedLoadingIndicator())
          : _sessions.isEmpty
          ? _EmptySolo(onCreate: _create, onHolyGrail: _createHolyGrail)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const SkinIcon(Icons.add),
                    label: const Text('新建跑团'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _createHolyGrail,
                    icon: const SkinIcon(Icons.auto_awesome),
                    label: const Text('圣杯战争：冬木残响'),
                  ),
                  const SizedBox(height: 16),
                  Text('跑团存档', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  ..._sessions.map(
                    (session) => Card(
                      child: ListTile(
                        onTap: () => _open(session),
                        leading: const CircleAvatar(
                          child: SkinIcon(Icons.explore),
                        ),
                        title: Text(session.title),
                        subtitle: Text(
                          '角色：${session.playerCharacters.firstOrNull?.name ?? '未创建'}\n'
                          '第 ${session.campaignState.currentAct} 幕 · '
                          '${session.worldState.location.isEmpty ? '未知地点' : session.worldState.location}',
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'delete') _delete(session);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'delete', child: Text('删除存档')),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: _sessions.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              icon: const SkinIcon(Icons.add),
              label: const Text('新建跑团'),
            ),
    );
  }
}

class _EmptySolo extends StatelessWidget {
  const _EmptySolo({required this.onCreate, required this.onHolyGrail});
  final VoidCallback onCreate, onHolyGrail;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkinIcon(
            Icons.explore_outlined,
            size: 88,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text('还没有冒险记录', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('创建你的第一场 AI 主持跑团'),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const SkinIcon(Icons.add),
            label: const Text('新建跑团'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onHolyGrail,
            icon: const SkinIcon(Icons.auto_awesome),
            label: const Text('开始圣杯战争'),
          ),
        ],
      ),
    ),
  );
}
