import '../../app/skins/skin_icon.dart';
import '../../app/skins/character_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/save_slot.dart';
import '../../models/api_profile.dart';
import '../../models/story_card.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../repositories/campaign_repository.dart';
import '../../repositories/save_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/story_card_repository.dart';
import '../../services/ai_service.dart';
import '../../services/ai_card_builder_service.dart';
import '../../services/ai_json_import_service.dart';
import '../../services/export_service.dart';
import '../../widgets/save_card.dart';
import '../../widgets/community_links.dart';
import '../app_settings/app_settings_screen.dart';
import '../card_builder/ai_card_builder_screen.dart';
import '../chat/chat_screen.dart';
import '../character_cards/character_card_screen.dart';
import '../cloud_share/cloud_upload_screen.dart';
import '../save_editor/save_editor_screen.dart';
import '../story_cards/story_card_details_dialog.dart';
import '../story_cards/story_card_screen.dart';
import '../world_expansion/save_world_expansion_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.repository,
    required this.storyCardRepository,
    required this.characterCardRepository,
    required this.campaignRepository,
    required this.apiRepository,
    required this.settingsRepository,
    required this.aiService,
    this.onExitToModes,
    super.key,
  });

  final SaveRepository repository;
  final StoryCardRepository storyCardRepository;
  final CharacterCardRepository characterCardRepository;
  final CampaignRepository campaignRepository;
  final ApiRepository apiRepository;
  final SettingsRepository settingsRepository;
  final AiService aiService;
  final VoidCallback? onExitToModes;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _exportService = ExportService();
  var _loading = true;
  var _aiImproveImport = false;
  var _importing = false;
  String? _error;
  List<SaveSlot> _saves = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final saves = await widget.repository.getAll();
      if (!mounted) return;
      setState(() {
        _saves = saves;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '读取存档失败：$error';
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final save = await Navigator.push<SaveSlot>(
      context,
      MaterialPageRoute(builder: (_) => const SaveEditorScreen()),
    );
    if (save == null) return;
    await _persist(save, successMessage: '存档已创建');
  }

  Future<SaveSlot?> _edit(SaveSlot save) async {
    final updated = await Navigator.push<SaveSlot>(
      context,
      MaterialPageRoute(builder: (_) => SaveEditorScreen(initialSave: save)),
    );
    if (updated == null) return null;
    final succeeded = await _persist(updated, successMessage: '存档已保存');
    return succeeded ? updated : null;
  }

  Future<bool> _persist(SaveSlot save, {required String successMessage}) async {
    try {
      await widget.repository.upsert(save);
      await _load();
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      return false;
    }
  }

  Future<void> _open(SaveSlot save) async {
    final played = save.copyWith(lastPlayedAt: DateTime.now());
    await widget.repository.upsert(played);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          save: played,
          saveRepository: widget.repository,
          characterCardRepository: widget.characterCardRepository,
          apiRepository: widget.apiRepository,
          settingsRepository: widget.settingsRepository,
          aiService: widget.aiService,
        ),
      ),
    );
    await _load();
  }

  Future<void> _delete(SaveSlot save) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除存档？'),
        content: Text('“${save.name}”的角色、世界设定和聊天记录都将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.delete(save.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已删除“${save.name}”')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  Future<void> _duplicate(SaveSlot save) async {
    try {
      await widget.repository.duplicate(save);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('存档副本已创建')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('复制失败：$error')));
    }
  }

  Future<void> _expandWorld(SaveSlot save) async {
    final complete = await widget.repository.getById(save.id) ?? save;
    if (!mounted) return;
    final updated = await Navigator.push<SaveSlot>(
      context,
      MaterialPageRoute(
        builder: (_) => SaveWorldExpansionScreen(
          save: complete,
          saveRepository: widget.repository,
          apiRepository: widget.apiRepository,
          settingsRepository: widget.settingsRepository,
          aiService: widget.aiService,
        ),
      ),
    );
    if (updated != null) await _load();
  }

  Future<void> _storeAsCard(SaveSlot save) async {
    try {
      final complete = await widget.repository.getById(save.id) ?? save;
      if (!mounted) return;
      final details = await showStoryCardDetailsDialog(
        context,
        initialName: save.name,
        initialDescription: save.scenario,
      );
      if (details == null) return;
      final card = StoryCard.fromSave(
        complete,
        name: details.name,
        description: details.description,
        author: details.author,
      );
      await widget.storyCardRepository.upsert(card);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('“${card.name}”已收藏到剧情卡片库')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('收藏卡片失败：$error')));
    }
  }

  Future<void> _openStoryCards() async {
    final save = await Navigator.push<SaveSlot>(
      context,
      MaterialPageRoute(
        builder: (_) => StoryCardScreen(
          repository: widget.storyCardRepository,
          saveRepository: widget.repository,
          apiRepository: widget.apiRepository,
          settingsRepository: widget.settingsRepository,
          aiService: widget.aiService,
        ),
      ),
    );
    await _load();
    if (save != null && mounted) await _open(save);
  }

  Future<void> _openCharacterCards() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterCardScreen(
          repository: widget.characterCardRepository,
          settingsRepository: widget.settingsRepository,
          campaignRepository: widget.campaignRepository,
        ),
      ),
    );
  }

  void _openCloudUpload() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => CloudUploadScreen(
        apiRepository: widget.apiRepository,
        characters: widget.characterCardRepository,
        stories: widget.storyCardRepository,
      ),
    ),
  );

  Future<void> _openAiCardBuilder() async {
    final save = await Navigator.push<SaveSlot>(
      context,
      MaterialPageRoute(
        builder: (_) => AiCardBuilderScreen(
          apiRepository: widget.apiRepository,
          settingsRepository: widget.settingsRepository,
          storyCardRepository: widget.storyCardRepository,
          characterCardRepository: widget.characterCardRepository,
          saveRepository: widget.repository,
          aiService: widget.aiService,
        ),
      ),
    );
    await _load();
    if (save != null && mounted) await _open(save);
  }

  Future<void> _openSettings() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => AppSettingsScreen(
        apiRepository: widget.apiRepository,
        settingsRepository: widget.settingsRepository,
        aiService: widget.aiService,
      ),
    ),
  );

  Future<void> _openFeatureCenter() async {
    final features =
        <
          ({
            IconData icon,
            String label,
            String description,
            Future<void> Function() action,
          })
        >[
          (
            icon: Icons.auto_awesome_outlined,
            label: 'AI 制卡工坊',
            description: '用文字或文档构筑卡片',
            action: _openAiCardBuilder,
          ),
          (
            icon: Icons.badge_outlined,
            label: '角色卡库',
            description: '管理与编辑角色',
            action: _openCharacterCards,
          ),
          (
            icon: Icons.style_outlined,
            label: '剧情卡片库',
            description: '官方与自制剧情',
            action: _openStoryCards,
          ),
          (
            icon: _aiImproveImport
                ? Icons.auto_fix_high_outlined
                : Icons.upload_file_outlined,
            label: '导入 JSON',
            description: '支持本地兼容与 AI 转换',
            action: _import,
          ),
          (
            icon: Icons.settings_outlined,
            label: '应用设置',
            description: 'API、记忆与语音',
            action: _openSettings,
          ),
          (
            icon: Icons.open_in_new,
            label: '网页社区',
            description: '发现作品、上传 JSON 与封面',
            action: () => openCommunityWebsite(context),
          ),
        ];
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('功能中心', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                '卡片、导入与设置都收纳在这里',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: features.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.55,
                ),
                itemBuilder: (context, index) {
                  final feature = features[index];
                  return Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _importing && feature.label == '导入 JSON'
                          ? null
                          : () async {
                              Navigator.pop(sheetContext);
                              await feature.action();
                            },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SkinIcon(feature.icon),
                            const SizedBox(height: 8),
                            Text(
                              feature.label,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              feature.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile.adaptive(
                  secondary: const SkinIcon(Icons.auto_fix_high_outlined),
                  title: const Text('AI 完善导入格式'),
                  subtitle: Text(
                    _aiImproveImport
                        ? '开启后，导入 JSON 时会调用 API 补全结构'
                        : '关闭时，仅在本地进行兼容转换',
                  ),
                  value: _aiImproveImport,
                  onChanged: _importing
                      ? null
                      : (value) {
                          setState(() => _aiImproveImport = value);
                          setSheetState(() {});
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _export(SaveSlot save) async {
    try {
      final complete = await widget.repository.getById(save.id) ?? save;
      final path = await _exportService.exportSave(complete);
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('存档已导出：$path')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
    }
  }

  Future<void> _import() async {
    try {
      final source = await _exportService.pickJsonSource(
        dialogTitle: _aiImproveImport ? '导入并由 AI 完善 JSON' : '导入存档或外部酒馆 JSON',
      );
      if (source == null) return;
      SaveSlot save;
      if (_aiImproveImport) {
        final settings = await widget.settingsRepository.load();
        final profiles = await widget.apiRepository.getAll();
        final profile = profiles.cast<ApiProfile?>().firstWhere(
          (item) => item?.id == settings.defaultApiProfileId,
          orElse: () => profiles.isEmpty ? null : profiles.first,
        );
        if (profile == null) {
          throw StateError('尚未配置 AI API，请先在应用设置中添加默认 API');
        }
        if (mounted) setState(() => _importing = true);
        final apiKey = await widget.apiRepository.readApiKey(profile.id);
        save = await AiJsonImportService(
          AiCardBuilderService(widget.aiService),
        ).convert(profile: profile, apiKey: apiKey, uploadedJson: source);
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认导入 AI 完善结果'),
            content: Text(
              '名称：${save.name}\n'
              '角色：${save.characters.length} 个\n'
              '世界书：${save.lorebook.length} 条\n\n'
              '${save.scenario.isEmpty ? '暂无剧情简介' : save.scenario}',
              maxLines: 14,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认写入'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      } else {
        save = _exportService.decodeImportedSave(source);
      }
      await widget.repository.upsert(save);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入“${save.name}”')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _handleAction(SaveSlot save, SaveAction action) {
    switch (action) {
      case SaveAction.edit:
        _edit(save);
      case SaveAction.aiExpandWorld:
        _expandWorld(save);
      case SaveAction.storeAsCard:
        _storeAsCard(save);
      case SaveAction.duplicate:
        _duplicate(save);
      case SaveAction.export:
        _export(save);
      case SaveAction.delete:
        _delete(save);
    }
  }

  Widget _body() {
    if (_loading) return const Center(child: ThemedLoadingIndicator());
    if (_error case final error?) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SkinIcon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_saves.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SkinIcon(
                  Icons.nightlife_outlined,
                  size: 88,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  '酒馆还很安静',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                const Text(
                  '创建第一个独立故事存档，设定玩家、世界观和剧情前提。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _create,
                  icon: const SkinIcon(Icons.add),
                  label: const Text('新建存档'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 430,
          mainAxisExtent: 210,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _saves.length,
        itemBuilder: (context, index) {
          final save = _saves[index];
          return SaveCard(
            save: save,
            onOpen: () => _open(save),
            onAction: (action) => _handleAction(save, action),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyU,
          control: true,
          shift: true,
        ): _openCloudUpload,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            leading: widget.onExitToModes == null
                ? null
                : IconButton(
                    tooltip: '模式主页',
                    onPressed: widget.onExitToModes,
                    icon: const SkinIcon(Icons.home_outlined),
                  ),
            titleSpacing: 16,
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('幻境酒馆'),
                Text('AI Tavern', style: TextStyle(fontSize: 12)),
              ],
            ),
            actions: [
              IconButton.filledTonal(
                tooltip: '功能中心',
                onPressed: _openFeatureCenter,
                icon: _importing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: ThemedLoadingIndicator(strokeWidth: 2),
                      )
                    : const SkinIcon(Icons.apps_rounded),
              ),
              IconButton(
                tooltip: '快捷上传到网页（Ctrl+Shift+U）',
                icon: const Icon(Icons.cloud_upload_outlined),
                onPressed: _openCloudUpload,
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: _body(),
          floatingActionButton: _saves.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: _create,
                  icon: const SkinIcon(Icons.add),
                  label: const Text('新建存档'),
                ),
        ),
      ),
    );
  }
}
