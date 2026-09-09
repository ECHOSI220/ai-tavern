import '../../app/skins/skin_icon.dart';
import 'package:flutter/material.dart';
import '../../app/skins/theme_craft.dart';
import '../../app/skins/skin_artwork.dart';

import '../../models/app_mode.dart';
import '../../models/save_slot.dart';
import '../../models/trpg_models.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../repositories/campaign_repository.dart';
import '../../repositories/save_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/story_card_repository.dart';
import '../../repositories/trpg_session_repository.dart';
import '../../services/ai_service.dart';
import '../../widgets/community_links.dart';
import '../home/home_screen.dart';
import '../app_settings/app_settings_screen.dart';
import '../multiplayer_trpg/multiplayer_home_screen.dart';
import '../rule_library/rule_library_screen.dart';
import '../solo_trpg/solo_trpg_home_screen.dart';

class PlatformHomeScreen extends StatefulWidget {
  const PlatformHomeScreen({
    required this.saveRepository,
    required this.storyCardRepository,
    required this.characterCardRepository,
    required this.campaignRepository,
    required this.trpgSessionRepository,
    required this.apiRepository,
    required this.settingsRepository,
    required this.aiService,
    super.key,
  });

  final SaveRepository saveRepository;
  final StoryCardRepository storyCardRepository;
  final CharacterCardRepository characterCardRepository;
  final CampaignRepository campaignRepository;
  final TRPGSessionRepository trpgSessionRepository;
  final ApiRepository apiRepository;
  final SettingsRepository settingsRepository;
  final AiService aiService;

  @override
  State<PlatformHomeScreen> createState() => _PlatformHomeScreenState();
}

class _PlatformHomeScreenState extends State<PlatformHomeScreen> {
  AppMode? _mode;
  SaveSlot? _recentTavern;
  TRPGSession? _recentSolo;
  TRPGSession? _recentMulti;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final tavern = await widget.saveRepository.getAll();
    final solo = await widget.trpgSessionRepository.getAll(mode: TRPGMode.solo);
    final multi = await widget.trpgSessionRepository.getAll(
      mode: TRPGMode.multiplayer,
    );
    if (!mounted) return;
    setState(() {
      _recentTavern = tavern.firstOrNull;
      _recentSolo = solo.firstOrNull;
      _recentMulti = multi.firstOrNull;
    });
  }

  void _openMode(AppMode mode) => setState(() => _mode = mode);
  void _returnHome() {
    setState(() => _mode = null);
    _loadRecent();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_mode) {
      AppMode.tavern => HomeScreen(
        repository: widget.saveRepository,
        storyCardRepository: widget.storyCardRepository,
        characterCardRepository: widget.characterCardRepository,
        campaignRepository: widget.campaignRepository,
        apiRepository: widget.apiRepository,
        settingsRepository: widget.settingsRepository,
        aiService: widget.aiService,
        onExitToModes: _returnHome,
      ),
      AppMode.soloTrpg => SoloTrpgHomeScreen(
        repository: widget.trpgSessionRepository,
        campaignRepository: widget.campaignRepository,
        characterRepository: widget.characterCardRepository,
        apiRepository: widget.apiRepository,
        settingsRepository: widget.settingsRepository,
        aiService: widget.aiService,
        onExitToModes: _returnHome,
      ),
      AppMode.multiplayerTrpg => MultiplayerHomeScreen(
        repository: widget.trpgSessionRepository,
        campaignRepository: widget.campaignRepository,
        characterRepository: widget.characterCardRepository,
        apiRepository: widget.apiRepository,
        settingsRepository: widget.settingsRepository,
        aiService: widget.aiService,
        onExitToModes: _returnHome,
      ),
      null => _ModeSelectionHome(
        recentTavern: _recentTavern,
        recentSolo: _recentSolo,
        recentMulti: _recentMulti,
        onSelect: _openMode,
        onOpenSettings: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => AppSettingsScreen(
              apiRepository: widget.apiRepository,
              settingsRepository: widget.settingsRepository,
              aiService: widget.aiService,
            ),
          ),
        ),
        onOpenRules: () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const RuleLibraryScreen()),
        ),
      ),
    };
  }
}

class _ModeSelectionHome extends StatelessWidget {
  const _ModeSelectionHome({
    required this.recentTavern,
    required this.recentSolo,
    required this.recentMulti,
    required this.onSelect,
    required this.onOpenSettings,
    required this.onOpenRules,
  });
  final SaveSlot? recentTavern;
  final TRPGSession? recentSolo;
  final TRPGSession? recentMulti;
  final ValueChanged<AppMode> onSelect;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenRules;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: onOpenRules,
            tooltip: '跑团规则资料库',
            icon: const SkinIcon(Icons.menu_book_outlined),
          ),
          IconButton(
            onPressed: onOpenSettings,
            tooltip: '应用设置',
            icon: const SkinIcon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: SkinArtworkTheme.of(context)?.immersiveArtwork == true
              ? Alignment.topCenter
              : Alignment.center,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (SkinCraft.of(context).refined)
                    const SkinWelcomeHeader()
                  else ...[
                    SkinIcon(
                      Icons.local_fire_department_outlined,
                      size: 44,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'AI TAVERN',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    Text(
                      '我的幻境酒馆',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '选择今天要进入的世界',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  const CommunityLinks(),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 840 ? 3 : 1;
                      final cards = [
                        PlatformModeCard(
                          mode: AppMode.tavern,
                          icon: Icons.forum_outlined,
                          description: '与你的角色进行自由聊天',
                          recentTitle: recentTavern?.name ?? '还没有聊天记录',
                          recentDetail: recentTavern == null
                              ? '创建第一个角色存档'
                              : '${recentTavern!.messageCount} 条消息',
                          onTap: () => onSelect(AppMode.tavern),
                        ),
                        PlatformModeCard(
                          mode: AppMode.soloTrpg,
                          icon: Icons.explore_outlined,
                          description: '由 AI 担任主持人的个人冒险',
                          recentTitle: recentSolo?.title ?? '还没有冒险记录',
                          recentDetail: recentSolo == null
                              ? '创建你的第一场跑团'
                              : '第 ${recentSolo!.campaignState.currentAct} 幕 · ${recentSolo!.worldState.location}',
                          onTap: () => onSelect(AppMode.soloTrpg),
                        ),
                        PlatformModeCard(
                          mode: AppMode.multiplayerTrpg,
                          icon: Icons.groups_outlined,
                          description: '与朋友一起进行 AI 跑团',
                          recentTitle: recentMulti?.title ?? '暂无进行中的房间',
                          recentDetail: recentMulti == null
                              ? '创建或加入本地模拟房间'
                              : '房间码 ${recentMulti!.metadata['roomCode'] ?? '--'}',
                          onTap: () => onSelect(AppMode.multiplayerTrpg),
                        ),
                      ];
                      if (columns == 1) {
                        return Column(
                          children: [
                            for (
                              var index = 0;
                              index < cards.length;
                              index++
                            ) ...[
                              cards[index],
                              if (index != cards.length - 1)
                                const SizedBox(height: 16),
                            ],
                          ],
                        );
                      }
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: columns,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.9,
                        children: cards,
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  Text('跑团工具', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      key: const ValueKey('open-rule-library'),
                      onTap: onOpenRules,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        child: const SkinIcon(Icons.menu_book_outlined),
                      ),
                      title: const Text('D&D 5E / COC 7版规则资料库'),
                      subtitle: const Text('检定、建卡、战斗、理智与快速开团指南'),
                      trailing: const SkinIcon(
                        Icons.arrow_forward_ios_rounded,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PlatformModeCard extends StatelessWidget {
  const PlatformModeCard({
    required this.mode,
    required this.icon,
    required this.description,
    required this.recentTitle,
    required this.recentDetail,
    required this.onTap,
    super.key,
  });
  final AppMode mode;
  final IconData icon;
  final String description, recentTitle, recentDetail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('mode-card-${mode.name}'),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (SkinCraft.of(context).refined)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: ShapeDecoration(
                      color:
                          SkinCraft.of(context).material ==
                                  SkinMaterial.digitalStage ||
                              SkinCraft.of(context).material ==
                                  SkinMaterial.clockworkVoice
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: .12)
                          : Theme.of(context).colorScheme.surfaceContainerLow,
                      shape:
                          SkinCraft.of(context).material ==
                                  SkinMaterial.digitalStage ||
                              SkinCraft.of(context).material ==
                                  SkinMaterial.clockworkVoice
                          ? CircleBorder(
                              side: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: .55),
                              ),
                            )
                          : SkinCraft.of(context).frame(ornament: false),
                    ),
                    child: SkinIcon(
                      icon,
                      size: 24,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                else
                  CircleAvatar(radius: 24, child: SkinIcon(icon, size: 26)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.label,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mode.subtitle,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SkinIcon(
                  Icons.arrow_forward_ios_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(description),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(
                  SkinCraft.of(context).refined ? 2 : 14,
                ),
                border: SkinCraft.of(context).refined
                    ? Border(
                        left: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      )
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('最近', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 5),
                  Text(
                    recentTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    recentDetail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
