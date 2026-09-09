import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../models/vision_settings.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/vision/vision_service.dart';

class VisionSettingsScreen extends StatefulWidget {
  const VisionSettingsScreen({
    required this.initialSettings,
    required this.settingsRepository,
    required this.apiRepository,
    super.key,
  });

  final AppSettings initialSettings;
  final SettingsRepository settingsRepository;
  final ApiRepository apiRepository;

  @override
  State<VisionSettingsScreen> createState() => _VisionSettingsScreenState();
}

class _VisionSettingsScreenState extends State<VisionSettingsScreen> {
  late AppSettings _settings;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  final _apiKey = TextEditingController();
  var _obscureKey = true;
  var _saving = false;
  var _testing = false;

  VisionSettings get _vision => _settings.visionSettings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _baseUrl = TextEditingController(text: _vision.baseUrl);
    _model = TextEditingController(text: _vision.model);
    _loadKey();
  }

  Future<void> _loadKey() async {
    final key = await widget.apiRepository.readVisionApiKey();
    if (mounted) _apiKey.text = key;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  VisionSettings _formValue() => _vision.copyWith(
    baseUrl: _baseUrl.text.trim(),
    model: _model.text.trim(),
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = _settings.copyWith(visionSettings: _formValue());
      await widget.settingsRepository.save(updated);
      await widget.apiRepository.writeVisionApiKey(_apiKey.text);
      if (!mounted) return;
      setState(() => _settings = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('看图设置已保存')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    final vision = _formValue();
    if (vision.provider != VisionProviderType.openAiCompatible) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前只实现了 OpenAI-Compatible Vision')),
      );
      return;
    }
    setState(() => _testing = true);
    try {
      final result = await VisionService().testConnection(
        settings: vision.copyWith(enabled: true),
        apiKey: _apiKey.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('视觉连接成功：$result')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('视觉连接失败：$error')));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _update(VisionSettings value) {
    setState(() => _settings = _settings.copyWith(visionSettings: value));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('看图能力'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile.adaptive(
              secondary: const Icon(Icons.visibility_outlined),
              title: const Text('启用图片理解'),
              subtitle: const Text(
                '图片会发送到你配置的 Vision 服务；识图结果再作为文字交给 DeepSeek 主模型。',
              ),
              value: _vision.enabled,
              onChanged: (value) => _update(_vision.copyWith(enabled: value)),
            ),
          ),
          const SizedBox(height: 12),
          Text('视觉服务', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<VisionProviderType>(
                    initialValue: _vision.provider,
                    decoration: const InputDecoration(
                      labelText: 'Vision Provider',
                      border: OutlineInputBorder(),
                    ),
                    items: VisionProviderType.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _update(_vision.copyWith(provider: value));
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _baseUrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'API Base URL',
                      hintText: 'https://example.com/v1',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _apiKey,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: 'Vision API Key',
                      helperText: '密钥只保存在系统安全存储，不写入数据库或导出文件',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        icon: Icon(
                          _obscureKey ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _model,
                    decoration: const InputDecoration(
                      labelText: 'Vision Model Name',
                      hintText: '例如 gpt-4.1-mini 或网关提供的视觉模型名',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check),
                      label: const Text('测试视觉连接'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('图片与分析', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.text_snippet_outlined),
                  title: const Text('启用 OCR'),
                  subtitle: const Text('尝试识别聊天截图、游戏界面、海报和书页文字'),
                  value: _vision.ocrEnabled,
                  onChanged: (value) =>
                      _update(_vision.copyWith(ocrEnabled: value)),
                ),
                ListTile(
                  title: const Text('最大图片数量'),
                  subtitle: Text('每条消息 ${_vision.maxImages} 张'),
                ),
                Slider(
                  min: 1,
                  max: 3,
                  divisions: 2,
                  label: '${_vision.maxImages}',
                  value: _vision.maxImages.toDouble(),
                  onChanged: (value) =>
                      _update(_vision.copyWith(maxImages: value.round())),
                ),
                ListTile(
                  title: const Text('最大图片尺寸'),
                  subtitle: Text('长边自动压缩至 ${_vision.maxImageDimension}px'),
                ),
                Slider(
                  min: 800,
                  max: 2400,
                  divisions: 8,
                  label: '${_vision.maxImageDimension}px',
                  value: _vision.maxImageDimension.toDouble().clamp(800, 2400),
                  onChanged: (value) => _update(
                    _vision.copyWith(maxImageDimension: value.round()),
                  ),
                ),
                ListTile(
                  title: const Text('分析超时'),
                  subtitle: Text('${_vision.timeoutSeconds} 秒'),
                ),
                Slider(
                  min: 15,
                  max: 120,
                  divisions: 7,
                  label: '${_vision.timeoutSeconds} 秒',
                  value: _vision.timeoutSeconds.toDouble(),
                  onChanged: (value) =>
                      _update(_vision.copyWith(timeoutSeconds: value.round())),
                ),
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.bug_report_outlined),
                  title: const Text('识图调试模式'),
                  subtitle: const Text('开启后可在图片消息下查看注入 DeepSeek 的识图摘要'),
                  value: _vision.debugMode,
                  onChanged: (value) =>
                      _update(_vision.copyWith(debugMode: value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.privacy_tip_outlined),
              title: Text('隐私提示'),
              subtitle: Text(
                '图片会上传到你自行配置的视觉 API。原图和精简识图结果保存在本机；Base64 不会写入存档。',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
