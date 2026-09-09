import 'package:flutter/material.dart';

import '../../models/api_profile.dart';
import '../../models/trpg_world_generator_models.dart';
import '../../repositories/api_repository.dart';
import '../../services/ai_service.dart';
import '../../services/trpg/world_generator.dart';

class AICampaignWizardScreen extends StatefulWidget {
  const AICampaignWizardScreen({
    required this.apiRepository,
    required this.aiService,
    super.key,
  });
  final ApiRepository apiRepository;
  final AiService aiService;
  @override
  State<AICampaignWizardScreen> createState() => _AICampaignWizardScreenState();
}

class _AICampaignWizardScreenState extends State<AICampaignWizardScreen> {
  final _genre = TextEditingController(text: '悬疑');
  final _setting = TextEditingController(text: '现代都市');
  final _players = TextEditingController(text: '3');
  final _length = TextEditingController(text: '3小时');
  final _style = TextEditingController(text: '严肃 + 少量幽默');
  final _difficulty = TextEditingController(text: '普通');
  final _era = TextEditingController(text: '近现代');
  final _technology = TextEditingController(text: '现代科技');
  final _magic = TextEditingController(text: '低魔法');
  final _keywords = TextEditingController();
  final _references = TextEditingController();
  final _favoriteCharacters = TextEditingController();
  final _forbiddenElements = TextEditingController();
  final _worldRules = TextEditingController();
  final _extra = TextEditingController();
  WorldGenerationLevel _level = WorldGenerationLevel.normal;
  bool _busy = false;
  String _stage = '';
  double _progress = 0;
  String? _error;

  Future<void> _generate() async {
    final profiles = await widget.apiRepository.getAll();
    final ApiProfile? profile = profiles.firstOrNull;
    if (profile == null) {
      setState(() => _error = '请先在设置中添加 API 配置');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _stage = '准备生成';
    });
    try {
      final key = await widget.apiRepository.readApiKey(profile.id);
      final result = await WorldGenerator(aiService: widget.aiService).generate(
        seed: WorldSeed(
          theme: _setting.text.trim(),
          genre: _genre.text.trim(),
          tone: _style.text.trim(),
          era: _era.text.trim(),
          technologyLevel: _technology.text.trim(),
          magicLevel: _magic.text.trim(),
          difficulty: _difficulty.text.trim(),
          playerCount: int.tryParse(_players.text.trim()) ?? 1,
          campaignLength: _length.text.trim(),
          level: _level,
          specialRules: _split(_extra.text),
          keywords: _split(_keywords.text),
          referenceWorks: _split(_references.text),
          favoriteCharacters: _split(_favoriteCharacters.text),
          forbiddenElements: _split(_forbiddenElements.text),
          worldRules: _split(_worldRules.text),
        ),
        profile: profile,
        apiKey: key,
        onProgress: (stage, progress) {
          if (mounted) {
            setState(() {
              _stage = stage;
              _progress = progress;
            });
          }
        },
      );
      if (mounted) Navigator.pop(context, result.campaign);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _split(String value) => value
      .split(RegExp(r'[,，;；\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 创建剧本')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'AI 会按世界骨架 → 地点图 → 势力 → NPC → 任务与生态分阶段生成，并写入现有 Campaign、WorldState、NPC Life 和存档系统。',
            ),
            const SizedBox(height: 16),
            _field(_genre, '类型'),
            _field(_setting, '主题 / 背景'),
            _field(_players, '人数'),
            _field(_length, '时长'),
            _field(_style, '风格'),
            _field(_difficulty, '难度'),
            DropdownButtonFormField<WorldGenerationLevel>(
              initialValue: _level,
              decoration: const InputDecoration(labelText: '世界生成等级'),
              items: const [
                DropdownMenuItem(
                  value: WorldGenerationLevel.quick,
                  child: Text('QUICK · 10分钟短团'),
                ),
                DropdownMenuItem(
                  value: WorldGenerationLevel.normal,
                  child: Text('NORMAL · 完整战役'),
                ),
                DropdownMenuItem(
                  value: WorldGenerationLevel.detailed,
                  child: Text('DETAILED · 长期世界'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(
                      () => _level = value ?? WorldGenerationLevel.normal,
                    ),
            ),
            const SizedBox(height: 10),
            _field(_era, '时代'),
            _field(_technology, '科技水平'),
            _field(_magic, '魔法 / 超自然水平'),
            _field(_keywords, '关键词（逗号分隔）'),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('高级自定义'),
              children: [
                _field(_references, '参考作品'),
                _field(_favoriteCharacters, '喜欢的角色类型'),
                _field(_forbiddenElements, '禁止元素'),
                _field(_worldRules, '世界规则'),
              ],
            ),
            TextField(
              controller: _extra,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: '补充要求（可选）'),
            ),
            const SizedBox(height: 20),
            if (_busy) ...[
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: 8),
              Text(_stage),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: widget.aiService.cancel,
                icon: const Icon(Icons.stop),
                label: const Text('取消生成'),
              ),
            ] else
              FilledButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('分阶段生成完整世界'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
    ),
  );
}
