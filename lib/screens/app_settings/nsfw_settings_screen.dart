import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_settings.dart';
import '../../models/nsfw_prompt_template.dart';
import '../../repositories/settings_repository.dart';

class NsfwSettingsScreen extends StatefulWidget {
  const NsfwSettingsScreen({
    required this.initialSettings,
    required this.settingsRepository,
    super.key,
  });

  final AppSettings initialSettings;
  final SettingsRepository settingsRepository;

  @override
  State<NsfwSettingsScreen> createState() => _NsfwSettingsScreenState();
}

class _NsfwSettingsScreenState extends State<NsfwSettingsScreen> {
  static const _uuid = Uuid();
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  Future<void> _save(AppSettings value) async {
    setState(() => _settings = value);
    await widget.settingsRepository.save(value);
  }

  Future<void> _editTemplate({NsfwPromptTemplate? template}) async {
    final name = TextEditingController(text: template?.name ?? '自定义提示词');
    final content = TextEditingController(text: template?.content ?? '');
    final result = await showDialog<NsfwPromptTemplate>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(template == null ? '新增自定义提示词' : '编辑自定义提示词'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: content,
                  minLines: 8,
                  maxLines: 18,
                  decoration: const InputDecoration(
                    labelText: '固定注入的提示词',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty || content.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                NsfwPromptTemplate(
                  id: template?.id ?? _uuid.v4(),
                  name: name.text.trim(),
                  content: content.text.trim(),
                  enabled: template?.enabled ?? true,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    name.dispose();
    content.dispose();
    if (result == null || !mounted) return;
    final templates = [..._settings.nsfwPromptTemplates];
    final index = templates.indexWhere((item) => item.id == result.id);
    if (index == -1) {
      templates.add(result);
    } else {
      templates[index] = result;
    }
    await _save(_settings.copyWith(nsfwPromptTemplates: templates));
  }

  Future<void> _deleteTemplate(NsfwPromptTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除自定义提示词？'),
        content: Text('将删除“${template.name}”，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _save(
      _settings.copyWith(
        nsfwPromptTemplates: _settings.nsfwPromptTemplates
            .where((item) => item.id != template.id)
            .toList(),
      ),
    );
  }

  Future<void> _toggleTemplate(NsfwPromptTemplate template, bool value) async {
    final templates = _settings.nsfwPromptTemplates
        .map(
          (item) =>
              item.id == template.id ? item.copyWith(enabled: value) : item,
        )
        .toList();
    await _save(_settings.copyWith(nsfwPromptTemplates: templates));
  }

  @override
  Widget build(BuildContext context) {
    final enabledCount = _settings.nsfwPromptTemplates
        .where((item) => item.enabled)
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('NSFW 提示词设置')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _editTemplate,
        icon: const Icon(Icons.add),
        label: const Text('新增提示词'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.no_adult_content_outlined),
              title: const Text('全局 NSFW 提示词'),
              subtitle: Text(
                _settings.nsfwEnabled
                    ? '已开启：所有剧情卡和存档固定注入 $enabledCount 组提示词'
                    : '已关闭：不会向游戏 API 请求注入下方提示词',
              ),
              value: _settings.nsfwEnabled,
              onChanged: (value) =>
                  _save(_settings.copyWith(nsfwEnabled: value)),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Text(
              '仅作用于游玩剧情、生成选项和“AI 帮我想”的系统提示词。它不能覆盖模型或 API 服务商自己的内容规则，也不保证模型一定照做。请确保场景只涉及虚构、成年且自愿的角色。',
            ),
          ),
          Text('提示词模板', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final template in _settings.nsfwPromptTemplates)
            Card(
              child: ExpansionTile(
                leading: Switch(
                  value: template.enabled,
                  onChanged: (value) => _toggleTemplate(template, value),
                ),
                title: Text(template.name),
                subtitle: Text(
                  template.builtIn ? '内置模板' : '自定义模板',
                  maxLines: 1,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(template.content),
                  ),
                  if (!template.builtIn) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _editTemplate(template: template),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('编辑'),
                        ),
                        TextButton.icon(
                          onPressed: () => _deleteTemplate(template),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('删除'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
