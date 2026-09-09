import 'package:flutter/material.dart';

import '../../models/memory_summary.dart';
import '../../models/save_slot.dart';
import '../../repositories/save_repository.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({
    required this.save,
    required this.repository,
    this.onGenerate,
    super.key,
  });

  final SaveSlot save;
  final SaveRepository repository;
  final Future<String> Function()? onGenerate;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  late final TextEditingController _controller;
  var _saving = false;
  var _generating = false;
  late bool _hasCompressedMemory;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.save.memorySummary.content,
    );
    _hasCompressedMemory = widget.save.memorySummary.content.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final now = DateTime.now();
    final updated = widget.save.copyWith(
      memorySummary: MemorySummary(
        content: _controller.text.trim(),
        updatedAt: now,
        coveredMessageId: widget.save.memorySummary.coveredMessageId,
      ),
      updatedAt: now,
    );
    await widget.repository.upsert(updated);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _hasCompressedMemory = _controller.text.trim().isNotEmpty;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('长期记忆已保存')));
  }

  Future<void> _generate() async {
    final generate = widget.onGenerate;
    if (generate == null) return;
    setState(() => _generating = true);
    try {
      final summary = await generate();
      if (!mounted) return;
      _controller.text = summary;
      setState(() => _hasCompressedMemory = summary.trim().isNotEmpty);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('剧情摘要已生成并保存')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('生成摘要失败：$error')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _deleteCompressedMemory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除压缩记忆？'),
        content: const Text('这会清空当前存档的长期压缩摘要，原始聊天记录不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除记忆'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final now = DateTime.now();
    final updated = widget.save.copyWith(
      memorySummary: MemorySummary(updatedAt: now),
      updatedAt: now,
    );
    await widget.repository.upsert(updated);
    _controller.clear();
    if (!mounted) return;
    setState(() => _hasCompressedMemory = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('压缩记忆已删除，原始聊天仍保留')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('压缩记忆'),
        actions: [
          if (_hasCompressedMemory)
            IconButton(
              tooltip: '删除压缩记忆',
              onPressed: _saving || _generating
                  ? null
                  : _deleteCompressedMemory,
              icon: const Icon(Icons.delete_outline),
            ),
          if (widget.onGenerate != null)
            IconButton(
              tooltip: '用 AI 生成摘要',
              onPressed: _generating ? null : _generate,
              icon: _generating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
            ),
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '压缩摘要会与尚未压缩的最近对话一起加入 Prompt，'
              '可随时人工修改、重新生成或删除。',
            ),
            if (widget.save.conversationMemory.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.history_toggle_off),
                  title: const Text('跨会话自动记忆'),
                  subtitle: const Text('每轮自动保存；退出并重新进入后仍会加入 Prompt'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [SelectableText(widget.save.conversationMemory)],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _controller,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: '记录已发生的关键事件、关系变化和未解线索……',
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存长期记忆'),
            ),
          ],
        ),
      ),
    );
  }
}
