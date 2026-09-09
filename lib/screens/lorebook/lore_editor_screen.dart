import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/lore_entry.dart';

class LoreEditorScreen extends StatefulWidget {
  const LoreEditorScreen({this.initialEntry, super.key});

  final LoreEntry? initialEntry;

  @override
  State<LoreEditorScreen> createState() => _LoreEditorScreenState();
}

class _LoreEditorScreenState extends State<LoreEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _keywords;
  late final TextEditingController _content;
  late final TextEditingController _priority;
  var _enabled = true;
  var _alwaysActive = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initialEntry;
    _title = TextEditingController(text: item?.title);
    _keywords = TextEditingController(text: item?.keywords.join(', '));
    _content = TextEditingController(text: item?.content);
    _priority = TextEditingController(text: '${item?.priority ?? 0}');
    _enabled = item?.enabled ?? true;
    _alwaysActive = item?.alwaysActive ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _keywords.dispose();
    _content.dispose();
    _priority.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final keywords = _keywords.text
        .split(RegExp(r'[,，\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    Navigator.pop(
      context,
      LoreEntry(
        id: widget.initialEntry?.id ?? const Uuid().v4(),
        title: _title.text.trim(),
        keywords: keywords,
        content: _content.text.trim(),
        alwaysActive: _alwaysActive,
        enabled: _enabled,
        priority: int.tryParse(_priority.text.trim()) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialEntry == null ? '新建世界书' : '编辑世界书'),
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
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: '标题'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入标题' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _keywords,
              decoration: const InputDecoration(
                labelText: '关键词',
                hintText: '用逗号或换行分隔，例如：骑士, 骑士团',
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _content,
              decoration: const InputDecoration(labelText: '内容'),
              minLines: 8,
              maxLines: 20,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入世界书内容' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priority,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '优先级',
                helperText: '数值越大，Prompt 中越靠前',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('始终加入 Prompt'),
              subtitle: const Text('开启后不需命中关键词'),
              value: _alwaysActive,
              onChanged: (value) => setState(() => _alwaysActive = value),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('保存世界书'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
