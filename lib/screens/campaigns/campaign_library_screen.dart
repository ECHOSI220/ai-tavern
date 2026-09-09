import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/campaign_models.dart';
import '../../models/trpg_models.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/campaign_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../services/ai_service.dart';
import '../../services/trpg/campaign_codec_service.dart';
import '../../services/trpg/campaign_template_service.dart';
import 'ai_campaign_wizard_screen.dart';
import 'campaign_editor_screen.dart';

class CampaignLibraryScreen extends StatefulWidget {
  const CampaignLibraryScreen({
    required this.repository,
    required this.characterRepository,
    required this.apiRepository,
    required this.aiService,
    super.key,
  });
  final CampaignRepository repository;
  final CharacterCardRepository characterRepository;
  final ApiRepository apiRepository;
  final AiService aiService;

  @override
  State<CampaignLibraryScreen> createState() => _CampaignLibraryScreenState();
}

class _CampaignLibraryScreenState extends State<CampaignLibraryScreen> {
  static const _codec = CampaignCodecService();
  List<CampaignDocument> _campaigns = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var campaigns = await widget.repository.getAll();
    const templates = CampaignTemplateService();
    final holyGrail = templates.holyGrailWar();
    if (campaigns.isEmpty) {
      await widget.repository.upsert(templates.mistHarbor());
      for (final template in templates.templates) {
        await widget.repository.upsert(template);
      }
      campaigns = await widget.repository.getAll();
    } else {
      final installed = campaigns
          .where((value) => value.id == holyGrail.id)
          .firstOrNull;
      final installedVersion =
          (installed?.metadata['holyGrailTemplateVersion'] as num?)?.toInt() ??
          0;
      if (installed == null ||
          (installed.source == CampaignSourceType.template &&
              installedVersion < 2)) {
        await widget.repository.upsert(holyGrail);
      }
      campaigns = await widget.repository.getAll();
    }
    if (!mounted) return;
    setState(() {
      _campaigns = campaigns;
      _loading = false;
    });
  }

  Future<void> _edit(CampaignDocument campaign) async {
    final saved = await Navigator.push<CampaignDocument>(
      context,
      MaterialPageRoute(
        builder: (_) => CampaignEditorScreen(
          initial: campaign,
          repository: widget.repository,
          characterRepository: widget.characterRepository,
        ),
      ),
    );
    if (saved != null) await _load();
  }

  Future<void> _create() async {
    await _edit(CampaignDocument.blank());
  }

  Future<void> _aiCreate() async {
    final campaign = await Navigator.push<CampaignDocument>(
      context,
      MaterialPageRoute(
        builder: (_) => AICampaignWizardScreen(
          apiRepository: widget.apiRepository,
          aiService: widget.aiService,
        ),
      ),
    );
    if (campaign == null || !mounted) return;
    await widget.repository.upsert(campaign);
    await _edit(campaign);
  }

  Future<void> _import() async {
    try {
      final campaign = await _codec.importFromFile();
      if (campaign == null) return;
      await widget.repository.upsert(campaign);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
      }
    }
  }

  Future<void> _duplicate(CampaignDocument source) async {
    final copy = CampaignDocument.fromJson(source.toJson()).copyWith(
      id: CampaignDocument.blank().id,
      title: '${source.title}（副本）',
      source: source.source,
      updatedAt: DateTime.now(),
    );
    await widget.repository.upsert(copy);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('剧本库'),
      actions: [
        IconButton(
          onPressed: _import,
          icon: const Icon(Icons.upload_file),
          tooltip: '导入 JSON',
        ),
        IconButton(
          onPressed: _aiCreate,
          icon: const Icon(Icons.auto_awesome),
          tooltip: 'AI 创建剧本',
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1100
                  ? 3
                  : constraints.maxWidth >= 700
                  ? 2
                  : 1;
              if (columns == 1) {
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
                  itemCount: _campaigns.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (_, index) => CampaignLibraryCard(
                    campaign: _campaigns[index],
                    compact: true,
                    onTap: () => _edit(_campaigns[index]),
                    onMenuSelected: (value) =>
                        _handleMenu(value, _campaigns[index]),
                  ),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  mainAxisExtent: 400,
                ),
                itemCount: _campaigns.length,
                itemBuilder: (_, index) => CampaignLibraryCard(
                  campaign: _campaigns[index],
                  onTap: () => _edit(_campaigns[index]),
                  onMenuSelected: (value) =>
                      _handleMenu(value, _campaigns[index]),
                ),
              );
            },
          ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('新建剧本'),
    ),
  );

  Future<void> _handleMenu(String value, CampaignDocument campaign) async {
    if (value == 'edit') await _edit(campaign);
    if (value == 'export') await _codec.exportToFile(campaign);
    if (value == 'copy') await _duplicate(campaign);
    if (value == 'delete') {
      await widget.repository.delete(campaign.id);
      await _load();
    }
  }
}

class CampaignLibraryCard extends StatelessWidget {
  const CampaignLibraryCard({
    required this.campaign,
    required this.onTap,
    required this.onMenuSelected,
    this.compact = false,
    super.key,
  });

  final CampaignDocument campaign;
  final VoidCallback onTap;
  final ValueChanged<String> onMenuSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('campaign-card-${campaign.id}'),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: compact ? _compactContent(context) : _wideContent(context),
    ),
  );

  Widget _compactContent(BuildContext context) => Padding(
    padding: const EdgeInsets.all(14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CampaignCover(campaign: campaign, width: 88, height: 112),
        const SizedBox(width: 14),
        Expanded(child: _details(context, compact: true)),
      ],
    ),
  );

  Widget _wideContent(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        height: 156,
        width: double.infinity,
        child: _CampaignCover(campaign: campaign),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
          child: _details(context),
        ),
      ),
    ],
  );

  Widget _details(BuildContext context, {bool compact = false}) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              campaign.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(height: 1.2),
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            onSelected: onMenuSelected,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(value: 'export', child: Text('导出 JSON')),
              PopupMenuItem(value: 'copy', child: Text('复制剧本')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        '${campaign.theme.isEmpty ? '未分类' : campaign.theme} · ${campaign.ruleSystem}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 3),
      Text('${campaign.recommendedPlayers}人 · 预计 ${campaign.estimatedLength}'),
      const SizedBox(height: 3),
      Text(
        '作者：${campaign.author.isEmpty ? '本地用户' : campaign.author} · ${campaign.source.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      if (campaign.tags.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: campaign.tags
              .take(compact ? 2 : 4)
              .map(
                (tag) => Chip(
                  label: Text(tag),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
              .toList(),
        ),
      ],
    ],
  );
}

class _CampaignCover extends StatelessWidget {
  const _CampaignCover({required this.campaign, this.width, this.height});

  final CampaignDocument campaign;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final cover = campaign.cover;
    final hasCover = cover != null && File(cover).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: height,
        child: hasCover
            ? Image.file(File(cover), fit: BoxFit.cover)
            : ColoredBox(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.36),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.auto_stories_outlined, size: 30),
                  ),
                ),
              ),
      ),
    );
  }
}
