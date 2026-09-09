import 'package:flutter/material.dart';
import '../../widgets/community_links.dart';

import '../../models/app_settings.dart';
import '../../models/trpg_presentation_models.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../api_settings/api_settings_screen.dart';
import 'nsfw_settings_screen.dart';
import 'voice_settings_screen.dart';
import 'vision_settings_screen.dart';
import 'skin_gallery_page.dart';
import '../../app/skins/theme_manager.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({
    required this.apiRepository,
    required this.settingsRepository,
    required this.aiService,
    super.key,
  });

  final ApiRepository apiRepository;
  final SettingsRepository settingsRepository;
  final AiService aiService;

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await widget.settingsRepository.load();
    if (mounted) setState(() => _settings = value);
  }

  Future<void> _update(AppSettings value) async {
    setState(() => _settings = value);
    await widget.settingsRepository.save(value);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('应用设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const CommunityLinks(),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('外观与皮肤'),
              subtitle: Text(
                ThemeScope.maybeOf(context)?.getCurrentTheme().name ??
                    '12 套皮肤 · 自定义背景',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: ThemeScope.maybeOf(context) == null
                  ? null
                  : () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SkinGalleryPage(),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: const Text('AI API 配置'),
              subtitle: const Text('管理 OpenAI-Compatible 地址、模型和密钥'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ApiSettingsScreen(
                    apiRepository: widget.apiRepository,
                    settingsRepository: widget.settingsRepository,
                    aiService: widget.aiService,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('看图能力'),
              subtitle: Text(
                settings.visionSettings.enabled
                    ? '${settings.visionSettings.provider.label} · ${settings.visionSettings.model.isEmpty ? '尚未填写模型' : settings.visionSettings.model}'
                    : '通过 Vision Proxy 识图，DeepSeek 主模型保持不变',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VisionSettingsScreen(
                      initialSettings: settings,
                      settingsRepository: widget.settingsRepository,
                      apiRepository: widget.apiRepository,
                    ),
                  ),
                );
                await _load();
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: const Text('语音'),
              subtitle: Text(
                settings.voiceSettings.speechInputEnabled ||
                        settings.voiceSettings.ttsEnabled
                    ? '语音输入或 AI 朗读已启用'
                    : '本地中英语音输入、VAD 与角色朗读',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VoiceSettingsScreen(
                      initialSettings: settings,
                      settingsRepository: widget.settingsRepository,
                    ),
                  ),
                );
                await _load();
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.no_adult_content_outlined),
              title: const Text('NSFW 提示词'),
              subtitle: Text(
                settings.nsfwEnabled
                    ? '全局开启 · ${settings.nsfwPromptTemplates.where((item) => item.enabled).length} 组已选'
                    : '全局关闭 · 可选择内置模板或添加自定义提示词',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NsfwSettingsScreen(
                      initialSettings: settings,
                      settingsRepository: widget.settingsRepository,
                    ),
                  ),
                );
                await _load();
              },
            ),
          ),
          const SizedBox(height: 12),
          Text('跑团设置', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.rule_outlined),
                  title: Text('默认规则'),
                  subtitle: Text('通用简易规则（Simple TRPG）'),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.save_outlined),
                  title: const Text('自动保存跑团进度'),
                  subtitle: const Text('玩家行动、掷骰、退出和进入后台时保存'),
                  value: settings.trpgAutoSave,
                  onChanged: (value) =>
                      _update(settings.copyWith(trpgAutoSave: value)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.casino_outlined),
                  title: const Text('3D 多面骰动画'),
                  value: settings.trpgDiceAnimation,
                  onChanged: (value) =>
                      _update(settings.copyWith(trpgDiceAnimation: value)),
                ),
                ListTile(
                  title: const Text('AI GM 默认模型'),
                  subtitle: const Text('默认沿用全局 AI API 配置，可在新建跑团时更换'),
                  trailing: const Icon(Icons.hub_outlined),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ApiSettingsScreen(
                        apiRepository: widget.apiRepository,
                        settingsRepository: widget.settingsRepository,
                        aiService: widget.aiService,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('GM 输出长度'),
                  subtitle: Text('${settings.trpgGmOutputLength} tokens'),
                ),
                Slider(
                  min: 500,
                  max: 4000,
                  divisions: 14,
                  label: '${settings.trpgGmOutputLength}',
                  value: settings.trpgGmOutputLength.toDouble(),
                  onChanged: (value) => _update(
                    settings.copyWith(trpgGmOutputLength: value.round()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.theater_comedy_outlined),
                  title: const Text('跑团演出模式'),
                  trailing: DropdownButton<PresentationMode>(
                    value: settings.trpgPresentationMode,
                    items: const [
                      DropdownMenuItem(
                        value: PresentationMode.immersive,
                        child: Text('沉浸'),
                      ),
                      DropdownMenuItem(
                        value: PresentationMode.classicChat,
                        child: Text('简洁文字'),
                      ),
                    ],
                    onChanged: (value) =>
                        _update(settings.copyWith(trpgPresentationMode: value)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.speed_outlined),
                  title: const Text('演出质量'),
                  trailing: DropdownButton<PresentationQuality>(
                    value: settings.trpgPresentationQuality,
                    items: const [
                      DropdownMenuItem(
                        value: PresentationQuality.simple,
                        child: Text('简洁'),
                      ),
                      DropdownMenuItem(
                        value: PresentationQuality.standard,
                        child: Text('标准'),
                      ),
                      DropdownMenuItem(
                        value: PresentationQuality.full,
                        child: Text('完整'),
                      ),
                    ],
                    onChanged: (value) => _update(
                      settings.copyWith(trpgPresentationQuality: value),
                    ),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.record_voice_over_outlined),
                  title: const Text('自动朗读旁白'),
                  value: settings.trpgAutoSpeakNarrator,
                  onChanged: (value) =>
                      _update(settings.copyWith(trpgAutoSpeakNarrator: value)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.voice_chat_outlined),
                  title: const Text('自动朗读 NPC'),
                  value: settings.trpgAutoSpeakNpc,
                  onChanged: (value) =>
                      _update(settings.copyWith(trpgAutoSpeakNpc: value)),
                ),
                ExpansionTile(
                  leading: const Icon(Icons.volume_up_outlined),
                  title: const Text('演出音量'),
                  children: [
                    _volumeSlider('总音量', settings.trpgMasterVolume, (value) {
                      _update(settings.copyWith(trpgMasterVolume: value));
                    }),
                    _volumeSlider('BGM', settings.trpgBgmVolume, (value) {
                      _update(settings.copyWith(trpgBgmVolume: value));
                    }),
                    _volumeSlider('环境音', settings.trpgAmbientVolume, (value) {
                      _update(settings.copyWith(trpgAmbientVolume: value));
                    }),
                    _volumeSlider('音效', settings.trpgSfxVolume, (value) {
                      _update(settings.copyWith(trpgSfxVolume: value));
                    }),
                    _volumeSlider('角色语音', settings.trpgVoiceVolume, (value) {
                      _update(settings.copyWith(trpgVoiceVolume: value));
                    }),
                  ],
                ),
                ListTile(
                  leading: const Icon(Icons.memory_outlined),
                  title: const Text('长期记忆上下文预算'),
                  subtitle: Text('${settings.trpgMemoryTokenBudget} tokens'),
                ),
                Slider(
                  min: 500,
                  max: 12000,
                  divisions: 23,
                  label: '${settings.trpgMemoryTokenBudget}',
                  value: settings.trpgMemoryTokenBudget.toDouble(),
                  onChanged: (value) => _update(
                    settings.copyWith(trpgMemoryTokenBudget: value.round()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('聊天', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('历史消息数量'),
                  subtitle: Text('${settings.historyMessageCount} 条'),
                ),
                Slider(
                  min: 20,
                  max: 120,
                  divisions: 5,
                  label: '${settings.historyMessageCount}',
                  value: settings.historyMessageCount.toDouble().clamp(20, 120),
                  onChanged: (value) => _update(
                    settings.copyWith(historyMessageCount: value.round()),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.compress),
                  title: const Text('自动压缩上下文'),
                  subtitle: Text(
                    settings.autoContextCompression
                        ? '每累计 ${settings.contextCompressionInterval} 条有效消息，用当前 API 合并为重要记忆'
                        : '关闭时不会额外调用 API；已有压缩记忆仍会保留',
                  ),
                  value: settings.autoContextCompression,
                  onChanged: (value) =>
                      _update(settings.copyWith(autoContextCompression: value)),
                ),
                if (settings.autoContextCompression) ...[
                  ListTile(
                    title: const Text('压缩频率'),
                    subtitle: Text(
                      settings.contextCompressionInterval == 2
                          ? '每轮对话后（2 条消息）'
                          : '每 ${settings.contextCompressionInterval} 条有效消息',
                    ),
                  ),
                  Slider(
                    min: 2,
                    max: 30,
                    divisions: 28,
                    label: '${settings.contextCompressionInterval}',
                    value: settings.contextCompressionInterval.toDouble().clamp(
                      2,
                      30,
                    ),
                    onChanged: (value) => _update(
                      settings.copyWith(
                        contextCompressionInterval: value.round(),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text('压缩会保留事件、关系、物品、承诺、未解线索和当前目标，并在后续请求中自动发送给 AI。'),
                  ),
                ],
                SwitchListTile(
                  title: const Text('默认流式输出'),
                  value: settings.streaming,
                  onChanged: (value) =>
                      _update(settings.copyWith(streaming: value)),
                ),
                SwitchListTile(
                  title: const Text('显示头像'),
                  value: settings.showAvatars,
                  onChanged: (value) =>
                      _update(settings.copyWith(showAvatars: value)),
                ),
                SwitchListTile(
                  title: const Text('自动滚动'),
                  value: settings.autoScroll,
                  onChanged: (value) =>
                      _update(settings.copyWith(autoScroll: value)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.auto_stories_outlined),
                  title: const Text('对话文风增强'),
                  subtitle: const Text('为每次 AI 回复注入活人感、小说感与沉浸式描写提示词'),
                  value: settings.dialogueImmersionEnabled,
                  onChanged: (value) => _update(
                    settings.copyWith(dialogueImmersionEnabled: value),
                  ),
                ),
                SwitchListTile(
                  title: const Text('调试模式'),
                  subtitle: const Text('不会记录 API Key 或完整私人对话'),
                  value: settings.debugMode,
                  onChanged: (value) =>
                      _update(settings.copyWith(debugMode: value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('外观', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('字体缩放'),
                  subtitle: Text('${(settings.fontScale * 100).round()}%'),
                ),
                Slider(
                  min: 0.8,
                  max: 1.4,
                  divisions: 6,
                  value: settings.fontScale.clamp(0.8, 1.4),
                  onChanged: (value) =>
                      _update(settings.copyWith(fontScale: value)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _volumeSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) => ListTile(
    title: Text(label),
    subtitle: Slider(
      min: 0,
      max: 1,
      divisions: 20,
      label: '${(value * 100).round()}%',
      value: value.clamp(0, 1),
      onChanged: onChanged,
    ),
  );
}
