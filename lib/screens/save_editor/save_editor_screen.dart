import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/save_slot.dart';
import '../../services/image_storage_service.dart';
import '../../models/play_mode.dart';

class SaveEditorScreen extends StatefulWidget {
  const SaveEditorScreen({this.initialSave, super.key});

  final SaveSlot? initialSave;

  @override
  State<SaveEditorScreen> createState() => _SaveEditorScreenState();
}

class _SaveEditorScreenState extends State<SaveEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _imageStorage = ImageStorageService();
  late final TextEditingController _name;
  late final TextEditingController _playerName;
  late final TextEditingController _playerDescription;
  late final TextEditingController _worldSetting;
  late final TextEditingController _scenario;
  late final TextEditingController _openingMessage;
  late final TextEditingController _roleplayRules;
  late PlayMode _playMode;
  late int _choiceCount;
  String? _coverImage;
  bool _pickingCover = false;

  @override
  void initState() {
    super.initState();
    final save = widget.initialSave;
    _name = TextEditingController(text: save?.name);
    _playerName = TextEditingController(text: save?.playerName);
    _playerDescription = TextEditingController(text: save?.playerDescription);
    _worldSetting = TextEditingController(text: save?.worldSetting);
    _scenario = TextEditingController(text: save?.scenario);
    _openingMessage = TextEditingController(text: save?.openingMessage);
    _roleplayRules = TextEditingController(
      text: save?.roleplayRules ?? defaultRoleplayRules,
    );
    _playMode = save?.playMode ?? PlayMode.freeform;
    _choiceCount = save?.choiceCount ?? 6;
    _coverImage = save?.coverImage;
  }

  @override
  void dispose() {
    _name.dispose();
    _playerName.dispose();
    _playerDescription.dispose();
    _worldSetting.dispose();
    _scenario.dispose();
    _openingMessage.dispose();
    _roleplayRules.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now();
    final existing = widget.initialSave;
    final result = existing == null
        ? SaveSlot.create(
            name: _name.text.trim(),
            coverImage: _coverImage,
            playerName: _playerName.text.trim(),
            playerDescription: _playerDescription.text.trim(),
            worldSetting: _worldSetting.text.trim(),
            scenario: _scenario.text.trim(),
            openingMessage: _openingMessage.text.trim(),
            roleplayRules: _roleplayRules.text.trim(),
            playMode: _playMode,
            choiceCount: _choiceCount,
          )
        : existing.copyWith(
            name: _name.text.trim(),
            coverImage: _coverImage,
            clearCoverImage: _coverImage == null,
            playerName: _playerName.text.trim(),
            playerDescription: _playerDescription.text.trim(),
            worldSetting: _worldSetting.text.trim(),
            scenario: _scenario.text.trim(),
            openingMessage: _openingMessage.text.trim(),
            roleplayRules: _roleplayRules.text.trim(),
            playMode: _playMode,
            choiceCount: _choiceCount,
            pendingChoices:
                existing.playMode == _playMode &&
                    existing.choiceCount == _choiceCount
                ? existing.pendingChoices
                : const [],
            updatedAt: now,
          );
    Navigator.pop(context, result);
  }

  Future<void> _pickCover() async {
    setState(() => _pickingCover = true);
    try {
      final path = await _imageStorage.pickAndStoreCover();
      if (mounted && path != null) setState(() => _coverImage = path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('选择封面失败：$error')));
    } finally {
      if (mounted) setState(() => _pickingCover = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int minLines = 1,
    int maxLines = 1,
    String? hint,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, hintText: hint),
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialSave == null ? '新建存档' : '编辑存档'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            AspectRatio(
              aspectRatio: 16 / 7,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _pickingCover ? null : _pickCover,
                  child: _coverImage == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, size: 42),
                            SizedBox(height: 8),
                            Text('从相册选择对话封面'),
                          ],
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(_coverImage!), fit: BoxFit.cover),
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Row(
                                children: [
                                  IconButton.filledTonal(
                                    tooltip: '更换封面',
                                    onPressed: _pickCover,
                                    icon: const Icon(Icons.photo_library),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton.filledTonal(
                                    tooltip: '移除封面',
                                    onPressed: () =>
                                        setState(() => _coverImage = null),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('基本信息', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            _field(
              _name,
              '存档名称 *',
              hint: '例如：银月酒馆',
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入存档名称' : null,
            ),
            _field(_playerName, '玩家名称', hint: '例如：旅行者'),
            _field(
              _playerDescription,
              '玩家设定',
              minLines: 3,
              maxLines: 6,
              hint: '允许为空',
            ),
            Text('玩法', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            SegmentedButton<PlayMode>(
              segments: const [
                ButtonSegment(
                  value: PlayMode.freeform,
                  icon: Icon(Icons.edit_note),
                  label: Text('普通玩法'),
                ),
                ButtonSegment(
                  value: PlayMode.choice,
                  icon: Icon(Icons.format_list_numbered),
                  label: Text('选项玩法'),
                ),
              ],
              selected: {_playMode},
              onSelectionChanged: (value) => setState(() {
                _playMode = value.first;
              }),
            ),
            const SizedBox(height: 8),
            Text(
              _playMode == PlayMode.freeform
                  ? '玩家自由输入行动或对白。'
                  : '每轮剧情后由 AI 提供可点击选项，玩家选择一个继续。',
            ),
            if (_playMode == PlayMode.choice) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('每轮选项数量'),
                  Expanded(
                    child: Slider(
                      value: _choiceCount.toDouble(),
                      min: 2,
                      max: 10,
                      divisions: 8,
                      label: '$_choiceCount',
                      onChanged: (value) => setState(() {
                        _choiceCount = value.round();
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '$_choiceCount',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Text('故事设定', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            _field(_worldSetting, '世界观', minLines: 5, maxLines: 12),
            _field(_scenario, '剧情前提', minLines: 5, maxLines: 12),
            _field(_openingMessage, '开场白', minLines: 3, maxLines: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('高级：角色扮演基础规则'),
              children: [
                _field(_roleplayRules, '系统规则', minLines: 8, maxLines: 18),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('保存存档'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
