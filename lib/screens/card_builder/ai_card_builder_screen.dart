import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_profile.dart';
import '../../models/card_build_target.dart';
import '../../models/character.dart';
import '../../models/story_card.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../repositories/save_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/story_card_repository.dart';
import '../../services/ai_card_builder_service.dart';
import '../../services/ai_service.dart';
import '../../services/card_source_document_service.dart';
import '../../services/export_service.dart';
import '../../services/world_expansion_service.dart';
import 'seed_character_picker_dialog.dart';

class AiCardBuilderScreen extends StatefulWidget {
  const AiCardBuilderScreen({
    required this.apiRepository,
    required this.settingsRepository,
    required this.storyCardRepository,
    required this.characterCardRepository,
    required this.saveRepository,
    required this.aiService,
    super.key,
  });

  final ApiRepository apiRepository;
  final SettingsRepository settingsRepository;
  final StoryCardRepository storyCardRepository;
  final CharacterCardRepository characterCardRepository;
  final SaveRepository saveRepository;
  final AiService aiService;

  @override
  State<AiCardBuilderScreen> createState() => _AiCardBuilderScreenState();
}

class _AiCardBuilderScreenState extends State<AiCardBuilderScreen> {
  final _sourceController = TextEditingController();
  final _documentService = const CardSourceDocumentService();
  final _exportService = ExportService();
  late final AiCardBuilderService _builderService;
  late final WorldExpansionService _worldExpansionService;

  CardBuildTarget _target = CardBuildTarget.story;
  List<ApiProfile> _profiles = const [];
  String? _selectedProfileId;
  CardSourceDocument? _document;
  AiCardBuildResult? _result;
  String? _error;
  String? _savedResultId;
  var _loading = true;
  var _generating = false;
  var _saving = false;
  var _expandWorld = false;
  String? _generationStatus;
  List<Character> _seedCharacters = const [];
  String? _worldExpansionPlan;
  Timer? _longWaitTimer;

  @override
  void initState() {
    super.initState();
    _builderService = AiCardBuilderService(widget.aiService);
    _worldExpansionService = WorldExpansionService(
      widget.aiService,
      _builderService,
    );
    _loadProfiles();
  }

  @override
  void dispose() {
    _longWaitTimer?.cancel();
    if (_generating) {
      if (_expandWorld) {
        _worldExpansionService.cancel();
      } else {
        _builderService.cancel();
      }
    }
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    try {
      final profiles = await widget.apiRepository.getAll();
      final settings = await widget.settingsRepository.load();
      final defaultExists = profiles.any(
        (item) => item.id == settings.defaultApiProfileId,
      );
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _selectedProfileId = defaultExists
            ? settings.defaultApiProfileId
            : profiles.firstOrNull?.id;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '读取 API 配置失败：$error';
        _loading = false;
      });
    }
  }

  Future<void> _pickDocument() async {
    try {
      final document = await _documentService.pickDocument();
      if (document == null || !mounted) return;
      setState(() {
        _document = document;
        _result = null;
        _savedResultId = null;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '读取文档失败：$error');
    }
  }

  String _combinedSource() {
    final buffer = StringBuffer();
    final document = _document;
    if (document != null) {
      buffer.writeln('【导入文档：${document.fileName}】');
      buffer.writeln(document.text);
    }
    final brief = _sourceController.text.trim();
    if (brief.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln('\n【用户补充说明】');
      buffer.write(brief);
    }
    return buffer.toString().trim();
  }

  Future<void> _pickSeedCharacters() async {
    try {
      final cards = await widget.characterCardRepository.getAll();
      if (!mounted) return;
      final selected = await showSeedCharacterPickerDialog(
        context,
        characters: cards,
        selected: _seedCharacters,
      );
      if (selected == null || !mounted) return;
      setState(() {
        _seedCharacters = selected;
        _result = null;
        _worldExpansionPlan = null;
        _savedResultId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '读取角色卡库失败：$error');
    }
  }

  Future<void> _generate() async {
    final source = _combinedSource();
    if (source.isEmpty && (!_expandWorld || _seedCharacters.isEmpty)) {
      setState(() => _error = '请先粘贴简易文字，或导入一个资料文档。');
      return;
    }
    final profile = _profiles
        .where((item) => item.id == _selectedProfileId)
        .firstOrNull;
    if (profile == null) {
      setState(() => _error = '尚未选择 API 配置，请先在应用设置中添加。');
      return;
    }

    setState(() {
      _generating = true;
      _result = null;
      _savedResultId = null;
      _error = null;
      _generationStatus = source.length > 22000
          ? '内容较大，预计可能超过 90 秒，请耐心等待；任务会持续运行直到完成。'
          : _document == null
          ? '正在生成……'
          : '正在本地整理导入文档……';
    });
    _longWaitTimer?.cancel();
    _longWaitTimer = Timer(const Duration(seconds: 90), () {
      if (!mounted || !_generating) return;
      setState(() {
        _generationStatus = '内容较大，请耐心等待；AI 仍在处理中，思考时间不受限制。';
      });
    });
    try {
      final apiKey = await widget.apiRepository.readApiKey(profile.id);
      final AiCardBuildResult result;
      if (_expandWorld) {
        final expanded = await _worldExpansionService.expand(
          profile: profile,
          apiKey: apiKey,
          seedCharacters: _seedCharacters,
          source: source,
          onProgress: (status) {
            if (mounted) setState(() => _generationStatus = status);
          },
        );
        _worldExpansionPlan = expanded.plan;
        result = AiCardBuildResult.story(expanded.storyCard);
      } else {
        result = await _builderService.build(
          target: _target,
          profile: profile,
          apiKey: apiKey,
          source: source,
          onProgress: (status) {
            if (mounted) setState(() => _generationStatus = status);
          },
        );
      }
      if (!mounted) return;
      setState(() => _result = result);
    } on AiCardBuildCancelled {
      if (!mounted) return;
      setState(() => _error = '本次生成已取消。');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '生成失败：$error');
    } finally {
      _longWaitTimer?.cancel();
      _longWaitTimer = null;
      if (mounted) {
        setState(() {
          _generating = false;
          _generationStatus = null;
        });
      }
    }
  }

  void _cancel() {
    if (_expandWorld) {
      _worldExpansionService.cancel();
    } else {
      _builderService.cancel();
    }
    setState(() => _error = '正在取消生成……');
  }

  Future<bool> _saveResult() async {
    final result = _result;
    if (result == null) return false;
    setState(() => _saving = true);
    try {
      if (result.storyCard case final card?) {
        await widget.storyCardRepository.upsert(card);
      } else if (result.character case final character?) {
        await widget.characterCardRepository.upsert(character);
      }
      if (!mounted) return false;
      setState(
        () => _savedResultId = result.storyCard?.id ?? result.character?.id,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('“${result.displayName}”已保存到${result.target.label}库'),
        ),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _error = '保存失败：$error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAndExport() async {
    if (!await _saveResult() || !mounted) return;
    try {
      final result = _result!;
      final path = result.storyCard != null
          ? await _exportService.exportStoryCard(result.storyCard!)
          : await _exportService.exportCharacter(result.character!);
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('卡片包已导出：$path')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '导出失败：$error');
    }
  }

  Future<void> _saveAndPlay() async {
    final card = _result?.storyCard;
    if (card == null || !await _saveResult()) return;
    try {
      final save = card.createSave();
      await widget.saveRepository.upsert(save);
      if (!mounted) return;
      Navigator.pop(context, save);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '创建游玩存档失败：$error');
    }
  }

  void _changeTarget(Set<CardBuildTarget> values) {
    if (values.isEmpty || _generating) return;
    setState(() {
      _target = values.first;
      if (_target == CardBuildTarget.character) {
        _expandWorld = false;
        _seedCharacters = const [];
      }
      _result = null;
      _worldExpansionPlan = null;
      _savedResultId = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 制卡工坊')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSourcePanel(),
                      if (_error case final error?) ...[
                        const SizedBox(height: 16),
                        MaterialBanner(
                          content: Text(error),
                          leading: const Icon(Icons.info_outline),
                          actions: [
                            TextButton(
                              onPressed: () => setState(() => _error = null),
                              child: const Text('知道了'),
                            ),
                          ],
                        ),
                      ],
                      if (_generating) ...[
                        const SizedBox(height: 20),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        Text(
                          _expandWorld
                              ? 'AI 正在先规划后续发展，再扩展完整世界观……'
                              : _combinedSource().length > 24000
                              ? '正在分段阅读长文并构筑卡片，请勿关闭页面……'
                              : 'AI 正在构筑完整卡片……',
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (_result case final result?) ...[
                        const SizedBox(height: 24),
                        _buildPreview(result),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSourcePanel() {
    final noProfiles = _profiles.isEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('1. 选择要制作的卡片', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SegmentedButton<CardBuildTarget>(
              segments: CardBuildTarget.values
                  .map(
                    (target) => ButtonSegment(
                      value: target,
                      icon: Icon(
                        target == CardBuildTarget.story
                            ? Icons.auto_stories_outlined
                            : Icons.person_outline,
                      ),
                      label: Text(target.label),
                    ),
                  )
                  .toList(),
              selected: {_target},
              onSelectionChanged: _changeTarget,
            ),
            const SizedBox(height: 8),
            Text(_target.description, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _expandWorld,
              onChanged: _generating
                  ? null
                  : (value) => setState(() {
                      _expandWorld = value;
                      if (value) _target = CardBuildTarget.story;
                      _result = null;
                      _worldExpansionPlan = null;
                      _savedResultId = null;
                    }),
              secondary: const Icon(Icons.public),
              title: const Text('扩展世界观'),
              subtitle: const Text('AI 先规划后续发展，再新增角色、势力、地点、规则和世界书'),
            ),
            if (_expandWorld) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _generating ? null : _pickSeedCharacters,
                icon: const Icon(Icons.group_add_outlined),
                label: Text(
                  _seedCharacters.isEmpty
                      ? '从角色卡库选择核心角色（可选）'
                      : '已选择 ${_seedCharacters.length} 个核心角色',
                ),
              ),
              if (_seedCharacters.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _seedCharacters
                      .map(
                        (character) => InputChip(
                          avatar: const Icon(Icons.person, size: 18),
                          label: Text(character.name),
                          onDeleted: _generating
                              ? null
                              : () => setState(() {
                                  _seedCharacters = _seedCharacters
                                      .where((item) => item.id != character.id)
                                      .toList();
                                  _result = null;
                                  _worldExpansionPlan = null;
                                }),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                '所选角色卡是不可修改的核心设定。可以只选角色，也可以再输入提示词或导入文档决定扩展方向。',
                style: TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
            Text('2. 提供创作资料', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            TextField(
              controller: _sourceController,
              minLines: 7,
              maxLines: 16,
              enabled: !_generating,
              onChanged: (_) {
                if (_result != null) {
                  setState(() {
                    _result = null;
                    _savedResultId = null;
                  });
                }
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
                labelText: '简易文字、剧情想法或补充要求',
                hintText: '例如：一位失去记忆的龙族医生，在漂浮城市寻找自己的过去……',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _generating ? null : _pickDocument,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('导入 TXT / Markdown / JSON / DOCX'),
                ),
                if (_document case final document?)
                  InputChip(
                    avatar: const Icon(Icons.description_outlined, size: 18),
                    label: Text(
                      '${document.fileName} · ${document.originalCharacterCount} 字符',
                    ),
                    onDeleted: _generating
                        ? null
                        : () => setState(() {
                            _document = null;
                            _result = null;
                            _savedResultId = null;
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '文档只在本地提取文字。超长文档会完整分段读取、逐段提炼并合并后制卡；预计超过 90 秒时会提示等待，但不会自动停止。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 24),
            Text('3. 选择制卡 API', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (noProfiles)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.warning_amber_outlined),
                title: Text('尚未配置 API'),
                subtitle: Text('请返回首页，在“应用设置”中添加并测试 API 后再生成。'),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedProfileId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'API 配置',
                ),
                items: _profiles
                    .map(
                      (profile) => DropdownMenuItem(
                        value: profile.id,
                        child: Text('${profile.name} · ${profile.model}'),
                      ),
                    )
                    .toList(),
                onChanged: _generating
                    ? null
                    : (value) => setState(() => _selectedProfileId = value),
              ),
            const SizedBox(height: 20),
            if (_generating && _generationStatus != null) ...[
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text(_generationStatus!),
                  subtitle: const Text('思考时间不受限制；只有主动取消或真实配置错误才会停止'),
                ),
              ),
            ],
            if (_generating)
              OutlinedButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('取消生成'),
              )
            else
              FilledButton.icon(
                onPressed: noProfiles ? null : _generate,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  _expandWorld ? 'AI 规划并扩展世界观' : '调用 API 构筑${_target.label}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(AiCardBuildResult result) {
    final saved =
        _savedResultId == (result.storyCard?.id ?? result.character?.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '生成预览：${result.displayName}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text(result.target.label)),
              ],
            ),
            const SizedBox(height: 12),
            if (result.character case final character?)
              _CharacterPreview(character: character)
            else if (result.storyCard case final card?)
              _StoryPreview(card: card),
            if (_worldExpansionPlan case final plan?) ...[
              const SizedBox(height: 8),
              _PreviewSection(title: 'AI 后续发展规划', content: plan),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _generate,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新生成'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _saveAndExport,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('保存并导出 JSON 包'),
                ),
                FilledButton.icon(
                  onPressed: _saving || saved ? null : _saveResult,
                  icon: Icon(saved ? Icons.check : Icons.save_outlined),
                  label: Text(saved ? '已保存到卡库' : '保存到${result.target.label}库'),
                ),
                if (result.storyCard != null)
                  FilledButton.tonalIcon(
                    onPressed: _saving ? null : _saveAndPlay,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('保存并开始游玩'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterPreview extends StatelessWidget {
  const _CharacterPreview({required this.character});

  final Character character;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PreviewSection(title: '角色定位', content: character.description),
        _PreviewSection(title: '性格', content: character.personality),
        _PreviewSection(title: '外貌', content: character.appearance),
        _PreviewSection(title: '背景', content: character.background),
        _PreviewSection(title: '说话方式', content: character.speakingStyle),
        _PreviewSection(title: '关系', content: character.relationship),
        _PreviewSection(title: '目标', content: character.goals),
        _PreviewSection(title: '秘密与伏笔', content: character.secrets),
        _PreviewSection(title: '示例对话', content: character.exampleDialogue),
        _PreviewSection(title: '场景备注', content: character.scenarioNotes),
      ],
    );
  }
}

class _StoryPreview extends StatelessWidget {
  const _StoryPreview({required this.card});

  final StoryCard card;

  @override
  Widget build(BuildContext context) {
    final save = card.template;
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(card.description),
          subtitle: Text(
            '作者：${card.author}　·　${save.characters.length} 个角色　·　'
            '${save.lorebook.length} 条世界书　·　${save.playMode.label}',
          ),
        ),
        _PreviewSection(title: '剧情框架', content: save.scenario),
        _PreviewSection(title: '世界观', content: save.worldSetting),
        _PreviewSection(title: '开场剧情', content: save.openingMessage),
        _PreviewSection(title: '扮演规则', content: save.roleplayRules),
        _PreviewSection(
          title: '角色（${save.characters.length}）',
          content: save.characters
              .map((item) => '${item.name}：${item.description}')
              .join('\n\n'),
        ),
        _PreviewSection(
          title: '世界书（${save.lorebook.length}）',
          content: save.lorebook
              .map((item) => '${item.title}：${item.content}')
              .join('\n\n'),
        ),
        _PreviewSection(title: '开局记忆', content: save.memorySummary.content),
      ],
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    if (content.trim().isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(title),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SizedBox(
            width: double.infinity,
            child: SelectableText(content),
          ),
        ),
      ],
    );
  }
}
