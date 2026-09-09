import 'package:flutter/material.dart';

import '../../models/trpg_memory_models.dart';
import '../../models/trpg_models.dart';
import '../../services/trpg_memory/memory_privacy_filter.dart';

class TRPGMemoryScreen extends StatefulWidget {
  const TRPGMemoryScreen({
    required this.session,
    required this.onChanged,
    this.playerId,
    this.isGm = false,
    this.debugMode = false,
    this.canEdit = true,
    super.key,
  });
  final TRPGSession session;
  final ValueChanged<TRPGSession> onChanged;
  final String? playerId;
  final bool isGm, debugMode, canEdit;

  @override
  State<TRPGMemoryScreen> createState() => _TRPGMemoryScreenState();
}

class _TRPGMemoryScreenState extends State<TRPGMemoryScreen> {
  final _search = TextEditingController();
  late TRPGSession _session = widget.session;

  @override
  Widget build(BuildContext context) {
    final access = MemoryAccessContext(
      requestingPlayerId: widget.playerId,
      channel: widget.isGm
          ? MemoryRequestChannel.gm
          : MemoryRequestChannel.playerPrivate,
      isGm: widget.isGm,
    );
    final query = _search.text.trim().toLowerCase();
    final visible =
        const MemoryPrivacyFilter()
            .filter(_session.memoryState.entries, access)
            .where(
              (memory) =>
                  query.isEmpty ||
                  [
                    memory.title,
                    memory.content,
                    ...memory.tags,
                  ].join(' ').toLowerCase().contains(query),
            )
            .toList()
          ..sort((a, b) => b.importance.compareTo(a.importance));
    final promises = _session.memoryState.promises.where(
      (value) =>
          widget.isGm ||
          value.promiser == widget.playerId ||
          value.promiseTo == widget.playerId,
    );
    final threads = _session.memoryState.storyThreads.where(
      (value) => widget.isGm || !value.gmOnly,
    );
    return Scaffold(
      appBar: AppBar(title: Text(widget.debugMode ? 'Memory Debug' : '冒险记录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: '搜索人物、地点、钥匙、承诺……',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (threads.isNotEmpty) ...[
            Text('未解决事件', style: Theme.of(context).textTheme.titleLarge),
            ...threads.map(
              (thread) => ListTile(
                leading: const Icon(Icons.alt_route),
                title: Text(thread.title),
                subtitle: Text('${thread.status.name} · ${thread.description}'),
              ),
            ),
          ],
          if (promises.isNotEmpty) ...[
            Text('承诺与债务', style: Theme.of(context).textTheme.titleLarge),
            ...promises.map(
              (promise) => ListTile(
                leading: const Icon(Icons.handshake_outlined),
                title: Text(promise.content),
                subtitle: Text(
                  '${promise.promiser} → ${promise.promiseTo} · ${promise.status.name}',
                ),
              ),
            ),
          ],
          Text('长期记忆', style: Theme.of(context).textTheme.titleLarge),
          if (visible.isEmpty) const ListTile(title: Text('暂无可见的长期记忆')),
          ...visible.map(
            (memory) => Card(
              child: ExpansionTile(
                leading: Icon(
                  memory.pinned ? Icons.push_pin : _icon(memory.type),
                ),
                title: Text(memory.title),
                subtitle: Text(
                  '重要度 ${memory.importance} · ${memory.confidence.name} · ${memory.resolved ? '已解决' : '未解决'}',
                ),
                childrenPadding: const EdgeInsets.all(16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(memory.content),
                  ),
                  if (widget.debugMode)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'visibility=${memory.visibility.name}\ncanon=${memory.canonPriority.name}\nentities=${memory.relatedEntityIds.join(', ')}\nsources=${memory.sourceEventIds.join(', ')}',
                      ),
                    ),
                  if (widget.isGm && widget.canEdit)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: memory.pinned ? '取消固定' : '固定',
                          onPressed: () =>
                              _update(memory.copyWith(pinned: !memory.pinned)),
                          icon: const Icon(Icons.push_pin_outlined),
                        ),
                        IconButton(
                          tooltip: '删除错误记忆',
                          onPressed: () => _delete(memory),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _update(MemoryEntry updated) {
    _session = _session.copyWith(
      memoryState: _session.memoryState.copyWith(
        entries: _session.memoryState.entries
            .map((value) => value.id == updated.id ? updated : value)
            .toList(),
      ),
    );
    widget.onChanged(_session);
    setState(() {});
  }

  void _delete(MemoryEntry memory) {
    _session = _session.copyWith(
      memoryState: _session.memoryState.copyWith(
        entries: _session.memoryState.entries
            .where((value) => value.id != memory.id)
            .toList(),
      ),
    );
    widget.onChanged(_session);
    setState(() {});
  }

  IconData _icon(MemoryType type) => switch (type) {
    MemoryType.promise => Icons.handshake_outlined,
    MemoryType.relationship => Icons.people_outline,
    MemoryType.secret ||
    MemoryType.privateMemory ||
    MemoryType.gmPlot => Icons.lock_outline,
    MemoryType.foreshadowing => Icons.visibility_outlined,
    MemoryType.clue => Icons.search,
    MemoryType.questMemory => Icons.assignment_outlined,
    MemoryType.companionMemory || MemoryType.npcMemory => Icons.person_outline,
    _ => Icons.bookmark_outline,
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}
