import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/character.dart';
import '../../models/app_settings.dart';
import '../../models/voice_settings.dart';
import '../../repositories/settings_repository.dart';
import '../../services/image_storage_service.dart';
import '../../services/voice/sherpa_text_to_speech_service.dart';
import '../../services/voice/voice_model_manager.dart';

class CharacterEditorScreen extends StatefulWidget {
  const CharacterEditorScreen({
    this.initialCharacter,
    this.settingsRepository,
    super.key,
  });

  final Character? initialCharacter;
  final SettingsRepository? settingsRepository;

  @override
  State<CharacterEditorScreen> createState() => _CharacterEditorScreenState();
}

class _CharacterEditorScreenState extends State<CharacterEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _imageStorage = ImageStorageService();
  late final Map<String, TextEditingController> _controllers;
  String? _avatar;
  var _enabled = true;
  var _pickingImage = false;
  AppSettings? _appSettings;
  CharacterVoiceConfig _voice = const CharacterVoiceConfig();
  var _previewingVoice = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initialCharacter;
    _avatar = item?.avatar;
    _enabled = item?.enabled ?? true;
    _controllers = {
      'name': TextEditingController(text: item?.name),
      'description': TextEditingController(text: item?.description),
      'personality': TextEditingController(text: item?.personality),
      'appearance': TextEditingController(text: item?.appearance),
      'background': TextEditingController(text: item?.background),
      'speakingStyle': TextEditingController(text: item?.speakingStyle),
      'relationship': TextEditingController(text: item?.relationship),
      'goals': TextEditingController(text: item?.goals),
      'secrets': TextEditingController(text: item?.secrets),
      'exampleDialogue': TextEditingController(text: item?.exampleDialogue),
      'scenarioNotes': TextEditingController(text: item?.scenarioNotes),
    };
    _loadVoice();
  }

  Future<void> _loadVoice() async {
    final repository = widget.settingsRepository;
    if (repository == null) return;
    final settings = await repository.load();
    final id = widget.initialCharacter?.id;
    if (!mounted) return;
    setState(() {
      _appSettings = settings;
      _voice = settings.voiceSettings.voiceFor(id);
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    setState(() => _pickingImage = true);
    try {
      final path = await _imageStorage.pickAndStoreAvatar();
      if (mounted && path != null) setState(() => _avatar = path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('选择头像失败：$error')));
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    String value(String key) => _controllers[key]!.text.trim();
    final existing = widget.initialCharacter;
    final character = Character(
      id: existing?.id ?? const Uuid().v4(),
      name: value('name'),
      avatar: _avatar,
      description: value('description'),
      personality: value('personality'),
      appearance: value('appearance'),
      background: value('background'),
      speakingStyle: value('speakingStyle'),
      relationship: value('relationship'),
      goals: value('goals'),
      secrets: value('secrets'),
      exampleDialogue: value('exampleDialogue'),
      scenarioNotes: value('scenarioNotes'),
      enabled: _enabled,
    );
    final repository = widget.settingsRepository;
    final settings = _appSettings;
    if (repository != null && settings != null) {
      final overrides = {...settings.voiceSettings.characterOverrides};
      overrides[character.id] = _voice;
      final updated = settings.copyWith(
        voiceSettings: settings.voiceSettings.copyWith(
          characterOverrides: overrides,
        ),
      );
      await repository.save(updated);
    }
    if (mounted) Navigator.pop(context, character);
  }

  Future<void> _previewVoice() async {
    setState(() => _previewingVoice = true);
    final manager = VoiceModelManager();
    final tts = SherpaTextToSpeechService(manager);
    try {
      await tts.speak(
        '你好，Commander，今天过得怎么样？ Hello, it is nice to meet you.',
        voice: _voice,
        speakNarration: true,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('试听失败：$error')));
      }
    } finally {
      await tts.dispose();
      manager.dispose();
      if (mounted) setState(() => _previewingVoice = false);
    }
  }

  Widget _field(
    String key,
    String label, {
    int minLines = 1,
    int maxLines = 1,
    String? hint,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: _controllers[key],
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: required
          ? (value) =>
                value == null || value.trim().isEmpty ? '请输入$label' : null
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialCharacter == null ? '新建角色' : '编辑角色'),
        actions: [
          TextButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 54,
                    backgroundImage: _avatar == null
                        ? null
                        : FileImage(File(_avatar!)),
                    child: _avatar == null
                        ? const Icon(Icons.person, size: 54)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: IconButton.filled(
                      tooltip: '选择头像',
                      onPressed: _pickingImage ? null : _pickAvatar,
                      icon: _pickingImage
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_camera_outlined),
                    ),
                  ),
                  if (_avatar != null)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: IconButton.filledTonal(
                        tooltip: '移除头像',
                        onPressed: () => setState(() => _avatar = null),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('加入当前 Prompt'),
              subtitle: const Text('关闭后角色资料暂时不发送给 AI'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            _field('name', '名字', required: true, hint: '例如：莉娅'),
            _field('description', '人物简介', minLines: 2, maxLines: 5),
            _field('personality', '性格', minLines: 3, maxLines: 8),
            _field('appearance', '外貌', minLines: 3, maxLines: 8),
            _field('background', '背景故事', minLines: 5, maxLines: 14),
            _field('relationship', '与玩家关系', minLines: 3, maxLines: 8),
            _field('speakingStyle', '说话方式', minLines: 3, maxLines: 8),
            _field('goals', '目标', minLines: 2, maxLines: 6),
            _field('secrets', '秘密', minLines: 3, maxLines: 10),
            _field(
              'exampleDialogue',
              '示例对白',
              minLines: 5,
              maxLines: 16,
              hint: '{{char}}：……\n{{user}}：……',
            ),
            _field('scenarioNotes', '场景备注', minLines: 2, maxLines: 6),
            if (widget.settingsRepository != null) ...[
              const SizedBox(height: 12),
              Text('角色语音', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('启用此角色语音'),
                      subtitle: const Text('配置只保存在本机，不写入角色卡 JSON'),
                      value: _voice.enabled,
                      onChanged: (value) => setState(
                        () => _voice = _voice.copyWith(enabled: value),
                      ),
                    ),
                    const ListTile(
                      leading: Icon(Icons.language_outlined),
                      title: Text('系统标准普通话'),
                      subtitle: Text('自动使用设备上最佳的 zh-CN 离线声音'),
                    ),
                    ListTile(
                      title: const Text('语速'),
                      subtitle: Text('${_voice.speed.toStringAsFixed(1)}x'),
                    ),
                    Slider(
                      min: 0.5,
                      max: 2,
                      divisions: 15,
                      value: _voice.speed,
                      onChanged: (value) => setState(
                        () => _voice = _voice.copyWith(speed: value),
                      ),
                    ),
                    ListTile(
                      title: const Text('音量'),
                      subtitle: Text('${(_voice.volume * 100).round()}%'),
                    ),
                    Slider(
                      min: 0,
                      max: 1,
                      divisions: 10,
                      value: _voice.volume,
                      onChanged: (value) => setState(
                        () => _voice = _voice.copyWith(volume: value),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('此角色自动朗读'),
                      value: _voice.autoSpeak,
                      onChanged: (value) => setState(
                        () => _voice = _voice.copyWith(autoSpeak: value),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _previewingVoice ? null : _previewVoice,
                          icon: _previewingVoice
                              ? const SizedBox.square(
                                  dimension: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow),
                          label: const Text('中英混合试听'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('保存角色'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
