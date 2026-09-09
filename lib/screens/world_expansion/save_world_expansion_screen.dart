import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_profile.dart';
import '../../models/save_slot.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/save_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_card_builder_service.dart';
import '../../services/ai_service.dart';
import '../../services/card_source_document_service.dart';
import '../../services/save_world_expansion_service.dart';
import '../../services/world_expansion_service.dart';

class SaveWorldExpansionScreen extends StatefulWidget {
  const SaveWorldExpansionScreen({
    required this.save,
    required this.saveRepository,
    required this.apiRepository,
    required this.settingsRepository,
    required this.aiService,
    super.key,
  });

  final SaveSlot save;
  final SaveRepository saveRepository;
  final ApiRepository apiRepository;
  final SettingsRepository settingsRepository;
  final AiService aiService;

  @override
  State<SaveWorldExpansionScreen> createState() =>
      _SaveWorldExpansionScreenState();
}

class _SaveWorldExpansionScreenState extends State<SaveWorldExpansionScreen> {
  final _guidance = TextEditingController();
  final _documentService = const CardSourceDocumentService();
  late final SaveWorldExpansionService _service;
  List<ApiProfile> _profiles = const [];
  String? _profileId;
  CardSourceDocument? _document;
  SaveWorldExpansionDraft? _draft;
  String? _status;
  String? _error;
  var _loading = true;
  var _generating = false;
  var _saving = false;
  Timer? _longWaitTimer;

  @override
  void initState() {
    super.initState();
    _service = SaveWorldExpansionService(
      WorldExpansionService(
        widget.aiService,
        AiCardBuilderService(widget.aiService),
      ),
    );
    _load();
  }

  Future<void> _load() async {
    try {
      final profiles = await widget.apiRepository.getAll();
      final settings = await widget.settingsRepository.load();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _profileId =
            profiles.any((item) => item.id == settings.defaultApiProfileId)
            ? settings.defaultApiProfileId
            : profiles.firstOrNull?.id;
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '读取 API 配置失败：$error');
    }
  }

  Future<void> _pickDocument() async {
    try {
      final document = await _documentService.pickDocument();
      if (document != null && mounted) {
        setState(() {
          _document = document;
          _draft = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '读取文档失败：$error');
    }
  }

  String _guidanceText() {
    final buffer = StringBuffer();
    if (_document case final document?) {
      buffer
        ..writeln('【用户导入的拓展参考：${document.fileName}】')
        ..writeln(document.text);
    }
    if (_guidance.text.trim().isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln('\n【用户补充提示词】');
      buffer.write(_guidance.text.trim());
    }
    return buffer.toString().trim();
  }

  Future<void> _generate() async {
    final profile = _profiles
        .where((item) => item.id == _profileId)
        .firstOrNull;
    if (profile == null) {
      setState(() => _error = '请先在应用设置中配置 AI API。');
      return;
    }
    setState(() {
      _generating = true;
      _draft = null;
      _error = null;
      _status = _guidanceText().length > 22000
          ? '内容较大，预计可能超过 90 秒，请耐心等待。'
          : '正在读取现有世界观并思考拓展方向……';
    });
    _longWaitTimer?.cancel();
    _longWaitTimer = Timer(const Duration(seconds: 90), () {
      if (mounted && _generating) {
        setState(() => _status = '内容较大，请耐心等待；AI 仍在拓展世界，思考时间不受限制。');
      }
    });
    try {
      final complete =
          await widget.saveRepository.getById(widget.save.id) ?? widget.save;
      final apiKey = await widget.apiRepository.readApiKey(profile.id);
      final draft = await _service.expand(
        save: complete,
        profile: profile,
        apiKey: apiKey,
        guidance: _guidanceText(),
        onProgress: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      if (mounted) setState(() => _draft = draft);
    } on AiCardBuildCancelled {
      if (mounted) setState(() => _error = '本次拓展已取消。');
    } catch (error) {
      if (mounted) setState(() => _error = '拓展失败：$error');
    } finally {
      _longWaitTimer?.cancel();
      if (mounted) {
        setState(() {
          _generating = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _apply() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      await widget.saveRepository.upsert(draft.expanded);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('世界观拓展已写入，游玩进度保持不变。')));
      Navigator.pop(context, draft.expanded);
    } catch (error) {
      if (mounted) setState(() => _error = '保存拓展失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancel() {
    _service.cancel();
    setState(() => _status = '正在取消……');
  }

  @override
  void dispose() {
    _longWaitTimer?.cancel();
    if (_generating) _service.cancel();
    _guidance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 拓展世界观')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: Text('基于“${widget.save.name}”增量拓展'),
                    subtitle: const Text(
                      '不会修改消息、长期记忆、剧情前提、开场白、当前选项、玩法模式或游玩时间线。',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _guidance,
                  enabled: !_generating,
                  minLines: 5,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: '拓展提示词（可留空）',
                    hintText: '留空时，AI 会根据现有世界观、角色和世界书自主延伸。',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
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
                        : () => setState(() => _document = null),
                  ),
                const SizedBox(height: 12),
                if (_profiles.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.warning_amber_outlined),
                    title: Text('尚未配置 AI API'),
                    subtitle: Text('请先前往应用设置添加 API。'),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _profileId,
                    decoration: const InputDecoration(
                      labelText: '拓展使用的 API',
                      border: OutlineInputBorder(),
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
                        : (value) => setState(() => _profileId = value),
                  ),
                const SizedBox(height: 14),
                if (_generating) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(_status ?? 'AI 正在拓展世界观……', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('取消拓展'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: _profiles.isEmpty ? null : _generate,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      _guidanceText().isEmpty ? '让 AI 自主思考并拓展' : '根据提示与文档拓展',
                    ),
                  ),
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(error),
                    ),
                  ),
                ],
                if (_draft case final draft?) ...[
                  const SizedBox(height: 20),
                  Text('拓展预览', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '新增世界设定',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            draft.addedWorldSetting.isEmpty
                                ? 'AI 没有生成独立的新世界设定。'
                                : draft.addedWorldSetting,
                          ),
                          if (draft.usedPlanningFallback) ...[
                            const SizedBox(height: 10),
                            Text(
                              '新角色/世界书的结构化输出不完整，已自动使用成功生成的世界观规划，不需要重试。',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                            ),
                          ],
                          const Divider(height: 28),
                          Text('新增角色：${draft.addedCharacters.length} 个'),
                          Text(
                            draft.addedCharacters.isEmpty
                                ? '无'
                                : draft.addedCharacters
                                      .map((item) => item.name)
                                      .join('、'),
                          ),
                          const SizedBox(height: 8),
                          Text('新增世界书：${draft.addedLore.length} 条'),
                          Text(
                            draft.addedLore.isEmpty
                                ? '无'
                                : draft.addedLore
                                      .map((item) => item.title)
                                      .join('、'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : _apply,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('确认写入世界资料'),
                  ),
                ],
              ],
            ),
    );
  }
}
