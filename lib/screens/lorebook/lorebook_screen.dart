import 'package:flutter/material.dart';

import '../../models/lore_entry.dart';
import '../../models/save_slot.dart';
import '../../repositories/save_repository.dart';
import 'lore_editor_screen.dart';

class LorebookScreen extends StatefulWidget {
  const LorebookScreen({
    required this.save,
    required this.repository,
    super.key,
  });

  final SaveSlot save;
  final SaveRepository repository;

  @override
  State<LorebookScreen> createState() => _LorebookScreenState();
}

class _LorebookScreenState extends State<LorebookScreen> {
  late SaveSlot _save;

  @override
  void initState() {
    super.initState();
    _save = widget.save;
  }

  Future<void> _persist(List<LoreEntry> entries) async {
    final updated = _save.copyWith(
      lorebook: entries,
      updatedAt: DateTime.now(),
    );
    await widget.repository.upsert(updated);
    if (mounted) setState(() => _save = updated);
  }

  Future<void> _edit([LoreEntry? entry]) async {
    final result = await Navigator.push<LoreEntry>(
      context,
      MaterialPageRoute(builder: (_) => LoreEditorScreen(initialEntry: entry)),
    );
    if (result == null) return;
    final list = [..._save.lorebook];
    final index = list.indexWhere((item) => item.id == result.id);
    if (index < 0) {
      list.add(result);
    } else {
      list[index] = result;
    }
    await _persist(list);
  }

  Future<void> _delete(LoreEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除世界书？'),
        content: Text('确认删除“${entry.title}”？'),
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
    if (confirmed == true) {
      await _persist(
        _save.lorebook.where((item) => item.id != entry.id).toList(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = [..._save.lorebook]
      ..sort((a, b) => b.priority.compareTo(a.priority));
    return Scaffold(
      appBar: AppBar(title: const Text('世界书')),
      body: entries.isEmpty
          ? const Center(child: Text('尚未创建世界书条目'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Card(
                  child: ListTile(
                    onTap: () => _edit(entry),
                    leading: Icon(
                      entry.alwaysActive
                          ? Icons.push_pin_outlined
                          : Icons.menu_book_outlined,
                    ),
                    title: Text(entry.title),
                    subtitle: Text(
                      entry.alwaysActive
                          ? '始终启用 · 优先级 ${entry.priority}'
                          : '${entry.keywords.join(' / ')} · 优先级 ${entry.priority}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: entry.enabled,
                          onChanged: (enabled) {
                            final list = [..._save.lorebook];
                            final originalIndex = list.indexWhere(
                              (item) => item.id == entry.id,
                            );
                            list[originalIndex] = entry.copyWith(
                              enabled: enabled,
                            );
                            _persist(list);
                          },
                        ),
                        IconButton(
                          onPressed: () => _delete(entry),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('新建条目'),
      ),
    );
  }
}
