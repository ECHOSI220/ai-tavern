import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../models/voice_settings.dart';
import '../../repositories/settings_repository.dart';
import '../../services/voice/voice_model_manager.dart';

class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({
    required this.initialSettings,
    required this.settingsRepository,
    super.key,
  });

  final AppSettings initialSettings;
  final SettingsRepository settingsRepository;

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  late AppSettings _settings;
  final _models = VoiceModelManager();
  final _statuses = <String, VoiceModelStatus>{};
  final _progress = <String, double?>{};
  final _errors = <String, String>{};

  static final _modelList = [
    VoiceModelManager.senseVoice,
    VoiceModelManager.sileroVad,
  ];

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _refreshModels();
  }

  @override
  void dispose() {
    _models.dispose();
    super.dispose();
  }

  Future<void> _saveVoice(VoiceSettings voice) async {
    final updated = _settings.copyWith(voiceSettings: voice);
    setState(() => _settings = updated);
    await widget.settingsRepository.save(updated);
  }

  Future<void> _refreshModels() async {
    for (final model in _modelList) {
      _statuses[model.id] = await _models.status(model);
    }
    if (mounted) setState(() {});
  }

  Future<void> _download(VoiceModelDescriptor model) async {
    setState(() {
      _progress[model.id] = 0;
      _errors.remove(model.id);
    });
    try {
      await _models.download(
        model,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _progress[model.id] = total == null || total == 0
                ? null
                : received / total;
          });
        },
      );
    } catch (error) {
      _errors[model.id] = error.toString();
    } finally {
      _progress.remove(model.id);
      await _refreshModels();
    }
  }

  Future<void> _delete(VoiceModelDescriptor model) async {
    await _models.delete(model);
    await _refreshModels();
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final voice = _settings.voiceSettings;
    return Scaffold(
      appBar: AppBar(title: const Text('语音设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('语音输入', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.mic_none),
                  title: const Text('启用语音输入'),
                  subtitle: const Text('使用本地 SenseVoice，不会上传录音'),
                  value: voice.speechInputEnabled,
                  onChanged: (value) =>
                      _saveVoice(voice.copyWith(speechInputEnabled: value)),
                ),
                ListTile(
                  title: const Text('识别语言'),
                  trailing: DropdownButton<SpeechLanguageMode>(
                    value: voice.recognitionLanguage,
                    items: const [
                      DropdownMenuItem(
                        value: SpeechLanguageMode.auto,
                        child: Text('自动／中英混说'),
                      ),
                      DropdownMenuItem(
                        value: SpeechLanguageMode.chinese,
                        child: Text('中文'),
                      ),
                      DropdownMenuItem(
                        value: SpeechLanguageMode.english,
                        child: Text('English'),
                      ),
                    ],
                    onChanged: (value) => value == null
                        ? null
                        : _saveVoice(
                            voice.copyWith(recognitionLanguage: value),
                          ),
                  ),
                ),
                ListTile(
                  title: const Text('语音输入模式'),
                  trailing: DropdownButton<SpeechInputMode>(
                    value: voice.inputMode,
                    items: const [
                      DropdownMenuItem(
                        value: SpeechInputMode.vadAutoStop,
                        child: Text('VAD 自动停止'),
                      ),
                      DropdownMenuItem(
                        value: SpeechInputMode.tapToStop,
                        child: Text('点击开始／点击结束'),
                      ),
                    ],
                    onChanged: (value) => value == null
                        ? null
                        : _saveVoice(voice.copyWith(inputMode: value)),
                  ),
                ),
                SwitchListTile(
                  title: const Text('识别后自动发送'),
                  subtitle: const Text('默认关闭；关闭时只填入输入框供修改'),
                  value: voice.autoSend,
                  onChanged: (value) =>
                      _saveVoice(voice.copyWith(autoSend: value)),
                ),
                ListTile(
                  title: const Text('识别文字处理'),
                  trailing: SegmentedButton<SpeechInsertMode>(
                    segments: const [
                      ButtonSegment(
                        value: SpeechInsertMode.append,
                        label: Text('追加'),
                      ),
                      ButtonSegment(
                        value: SpeechInsertMode.replace,
                        label: Text('替换'),
                      ),
                    ],
                    selected: {voice.insertMode},
                    onSelectionChanged: (value) =>
                        _saveVoice(voice.copyWith(insertMode: value.first)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('AI 文字朗读', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_outlined),
                  title: const Text('启用文字朗读'),
                  subtitle: const Text('使用设备内置的轻量标准普通话'),
                  value: voice.ttsEnabled,
                  onChanged: (value) =>
                      _saveVoice(voice.copyWith(ttsEnabled: value)),
                ),
                const ListTile(
                  leading: Icon(Icons.language_outlined),
                  title: Text('系统标准普通话'),
                  subtitle: Text('无需下载语音包，自动选择设备上最佳的 zh-CN 离线声音'),
                ),
                SwitchListTile(
                  title: const Text('AI 回复完成后自动朗读'),
                  value: voice.autoSpeak,
                  onChanged: (value) =>
                      _saveVoice(voice.copyWith(autoSpeak: value)),
                ),
                SwitchListTile(
                  title: const Text('朗读动作与旁白'),
                  value: voice.speakNarration,
                  onChanged: (value) =>
                      _saveVoice(voice.copyWith(speakNarration: value)),
                ),
                ListTile(
                  title: const Text('默认语速'),
                  subtitle: Text('${voice.defaultSpeed.toStringAsFixed(1)}x'),
                ),
                Slider(
                  min: 0.5,
                  max: 2,
                  divisions: 15,
                  value: voice.defaultSpeed,
                  onChanged: (value) =>
                      _saveVoice(voice.copyWith(defaultSpeed: value)),
                ),
                ListTile(
                  title: const Text('默认音量'),
                  subtitle: Text('${(voice.defaultVolume * 100).round()}%'),
                ),
                Slider(
                  min: 0,
                  max: 1,
                  divisions: 10,
                  value: voice.defaultVolume,
                  onChanged: (value) =>
                      _saveVoice(voice.copyWith(defaultVolume: value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('离线模型', style: Theme.of(context).textTheme.titleMedium),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '模型保存在应用专用 models 目录，不会打进 APK。首次使用前请下载；下载页显示服务器返回的真实进度和本地实际占用。',
            ),
          ),
          for (final model in _modelList) _modelCard(model),
        ],
      ),
    );
  }

  Widget _modelCard(VoiceModelDescriptor model) {
    final status = _statuses[model.id];
    final downloading = _progress.containsKey(model.id);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              model.kind == VoiceModelKind.asr
                  ? Icons.transcribe
                  : model.kind == VoiceModelKind.tts
                  ? Icons.record_voice_over
                  : Icons.graphic_eq,
            ),
            title: Text(model.name),
            subtitle: Text(
              status?.installed == true
                  ? '已安装 · ${_size(status!.bytes)}'
                  : '未安装${status != null && status.bytes > 0 ? ' · 已下载 ${_size(status.bytes)}' : ''}',
            ),
            trailing: downloading
                ? IconButton(
                    tooltip: '取消下载',
                    onPressed: () => _models.cancelDownload(model),
                    icon: const Icon(Icons.close),
                  )
                : status?.installed == true
                ? TextButton(
                    onPressed: () => _delete(model),
                    child: const Text('删除'),
                  )
                : FilledButton.tonal(
                    onPressed: () => _download(model),
                    child: const Text('下载'),
                  ),
          ),
          if (downloading) LinearProgressIndicator(value: _progress[model.id]),
          if (_errors[model.id] case final error?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
