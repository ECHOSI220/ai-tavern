import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/save_slot.dart';
import '../../models/story_card.dart';
import '../../models/api_profile.dart';
import '../../repositories/save_repository.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_card_builder_service.dart';
import '../../services/ai_json_import_service.dart';
import '../../services/ai_service.dart';
import '../../repositories/story_card_repository.dart';
import '../../services/export_service.dart';
import '../save_editor/save_editor_screen.dart';
import 'story_card_details_dialog.dart';

enum StoryCardAction { edit, export, delete }

enum StoryCardLaunchAction { continueGame, newGame }

class StoryCardScreen extends StatefulWidget {
  const StoryCardScreen({
    required this.repository,
    required this.saveRepository,
    this.apiRepository,
    this.settingsRepository,
    this.aiService,
    super.key,
  });

  final StoryCardRepository repository;
  final SaveRepository saveRepository;
  final ApiRepository? apiRepository;
  final SettingsRepository? settingsRepository;
  final AiService? aiService;

  @override
  State<StoryCardScreen> createState() => _StoryCardScreenState();
}

class _StoryCardScreenState extends State<StoryCardScreen> {
  final _exportService = ExportService();
  var _loading = true;
  String? _error;
  List<StoryCard> _cards = const [];
  List<SaveSlot> _saves = const [];
  var _aiImproveImport = false;
  var _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.repository.getAll(),
        widget.saveRepository.getAll(),
      ]);
      final cards = results[0] as List<StoryCard>;
      final saves = results[1] as List<SaveSlot>;
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _saves = saves;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取剧情卡片失败：$error';
      });
    }
  }

  Future<void> _create() async {
    final template = await Navigator.push<SaveSlot>(
      context,
      MaterialPageRoute(builder: (_) => const SaveEditorScreen()),
    );
    if (template == null || !mounted) return;
    final details = await showStoryCardDetailsDialog(
      context,
      initialName: template.name,
    );
    if (details == null) return;
    final card = StoryCard.fromSave(
      template,
      name: details.name,
      description: details.description,
      author: details.author,
    );
    await widget.repository.upsert(card);
    await _load();
  }

  Future<void> _edit(StoryCard card) async {
    if (card.isOfficial) return;
    final template = await Navigator.push<SaveSlot>(
      context,
      MaterialPageRoute(
        builder: (_) => SaveEditorScreen(initialSave: card.template),
      ),
    );
    if (template == null || !mounted) return;
    final details = await showStoryCardDetailsDialog(
      context,
      initialName: card.name,
      initialDescription: card.description,
      initialAuthor: card.author,
    );
    if (details == null) return;
    final cleaned = StoryCard.fromSave(template);
    await widget.repository.upsert(
      card.copyWith(
        name: details.name,
        description: details.description,
        author: details.author,
        template: cleaned.template,
        updatedAt: DateTime.now(),
      ),
    );
    await _load();
  }

  Future<void> _use(StoryCard card) async {
    try {
      final existing =
          _saves
              .where(
                (save) =>
                    save.sourceStoryCardId == card.id ||
                    (save.sourceStoryCardId == null && save.name == card.name),
              )
              .toList()
            ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));

      if (existing.isNotEmpty) {
        final action = await showDialog<StoryCardLaunchAction>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('已有游戏进度'),
            content: Text(
              '“${card.name}”已有 ${existing.length} 个存档。\n\n'
              '选择“继续游戏”会从最近的对话接着玩；'
              '只有选择“新开游戏”才会从头开始。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, StoryCardLaunchAction.newGame),
                child: const Text('新开游戏'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, StoryCardLaunchAction.continueGame),
                child: const Text('继续游戏'),
              ),
            ],
          ),
        );
        if (!mounted || action == null) return;
        if (action == StoryCardLaunchAction.continueGame) {
          var save =
              await widget.saveRepository.getById(existing.first.id) ??
              existing.first;
          if (save.sourceStoryCardId == null) {
            save = save.copyWith(sourceStoryCardId: card.id);
            await widget.saveRepository.upsert(save);
          }
          if (!mounted) return;
          Navigator.pop(context, save);
          return;
        }
      }

      final save = card.createSave();
      await widget.saveRepository.upsert(save);
      if (!mounted) return;
      Navigator.pop(context, save);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('使用卡片失败：$error')));
    }
  }

  Future<void> _delete(StoryCard card) async {
    if (card.isOfficial) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除剧情卡片？'),
        content: Text('只会删除“${card.name}”卡片，不影响已创建的游玩存档。'),
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
    await widget.repository.delete(card.id);
    await _load();
  }

  Future<void> _export(StoryCard card) async {
    try {
      final path = await _exportService.exportStoryCard(card);
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('卡片已导出：$path')));
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
        dialogTitle: _aiImproveImport
            ? '导入并由 AI 完善剧情卡 JSON'
            : '导入剧情卡、存档或外部酒馆 JSON',
      );
      if (source == null) return;
      StoryCard card;
      if (_aiImproveImport) {
        final apiRepository = widget.apiRepository;
        final settingsRepository = widget.settingsRepository;
        final aiService = widget.aiService;
        if (apiRepository == null ||
            settingsRepository == null ||
            aiService == null) {
          throw StateError('当前页面没有可用的 AI 导入配置');
        }
        final settings = await settingsRepository.load();
        final profiles = await apiRepository.getAll();
        final profile = profiles.cast<ApiProfile?>().firstWhere(
          (item) => item?.id == settings.defaultApiProfileId,
          orElse: () => profiles.isEmpty ? null : profiles.first,
        );
        if (profile == null) throw StateError('尚未配置 AI API');
        if (mounted) setState(() => _importing = true);
        final apiKey = await apiRepository.readApiKey(profile.id);
        final save = await AiJsonImportService(
          AiCardBuilderService(aiService),
        ).convert(profile: profile, apiKey: apiKey, uploadedJson: source);
        final generated = StoryCard.fromSave(
          save,
          description: save.scenario,
          author: 'AI 格式完善',
        );
        card = generated.copyWith(
          template: generated.template.copyWith(
            pendingChoices: save.pendingChoices,
            memorySummary: save.memorySummary.copyWith(
              clearCoveredMessageId: true,
            ),
          ),
        );
      } else {
        card = _exportService.decodeImportedStoryCard(source);
      }
      await widget.repository.upsert(card);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入“${card.name}”')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _handleAction(StoryCard card, StoryCardAction action) {
    switch (action) {
      case StoryCardAction.edit:
        _edit(card);
      case StoryCardAction.export:
        _export(card);
      case StoryCardAction.delete:
        _delete(card);
    }
  }

  Widget _card(StoryCard card) {
    final existing = _saves.where(
      (save) =>
          save.sourceStoryCardId == card.id ||
          (save.sourceStoryCardId == null && save.name == card.name),
    );
    final hasProgress = existing.isNotEmpty;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundImage:
                      card.template.coverImage != null &&
                          File(card.template.coverImage!).existsSync()
                      ? FileImage(File(card.template.coverImage!))
                      : null,
                  child:
                      card.template.coverImage == null ||
                          !File(card.template.coverImage!).existsSync()
                      ? Icon(card.isOfficial ? Icons.verified : Icons.style)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    card.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                PopupMenuButton<StoryCardAction>(
                  tooltip: '卡片操作',
                  onSelected: (action) => _handleAction(card, action),
                  itemBuilder: (_) => [
                    if (!card.isOfficial)
                      const PopupMenuItem(
                        value: StoryCardAction.edit,
                        child: Text('编辑卡片'),
                      ),
                    const PopupMenuItem(
                      value: StoryCardAction.export,
                      child: Text('导出卡片 JSON'),
                    ),
                    if (!card.isOfficial)
                      const PopupMenuItem(
                        value: StoryCardAction.delete,
                        child: Text('删除卡片'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (card.isOfficial)
              const Chip(
                avatar: Icon(Icons.verified, size: 16),
                label: Text('官方剧情'),
                visualDensity: VisualDensity.compact,
              ),
            Text(
              card.description.isEmpty ? '暂无简介' : card.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Text(
              '${card.template.characters.length} 个角色 · '
              '${card.template.lorebook.length} 条世界书 · '
              '${card.template.playMode.label}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _use(card),
                icon: Icon(hasProgress ? Icons.history : Icons.play_arrow),
                label: Text(hasProgress ? '继续游戏' : '使用卡片开始新存档'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error case final error?) {
      return Center(
        child: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(error),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 420,
        mainAxisExtent: 300,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _cards.length,
      itemBuilder: (_, index) => _card(_cards[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('剧情卡片库'),
        actions: [
          Tooltip(
            message: _aiImproveImport ? 'AI 完善格式已开启' : 'AI 完善格式已关闭',
            child: SizedBox(
              width: 42,
              child: Transform.scale(
                scale: 0.72,
                child: Switch.adaptive(
                  value: _aiImproveImport,
                  onChanged: widget.apiRepository == null || _importing
                      ? null
                      : (value) => setState(() => _aiImproveImport = value),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _aiImproveImport ? '导入 JSON（AI 完善格式）' : '导入外部或原生 JSON',
            onPressed: _importing ? null : _import,
            icon: _importing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _aiImproveImport
                        ? Icons.auto_fix_high_outlined
                        : Icons.upload_file,
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _body(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_card),
        label: const Text('新建卡片'),
      ),
    );
  }
}
