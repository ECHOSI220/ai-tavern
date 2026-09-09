import 'package:flutter/material.dart';
import '../../models/trpg_models.dart';
import '../../repositories/trpg_session_repository.dart';
import '../../services/trpg/multiplayer_archive_service.dart';

class LocalArchivesScreen extends StatefulWidget {
  const LocalArchivesScreen({required this.repository, required this.onPlay, required this.onBackup, super.key});
  final TRPGSessionRepository repository;
  final Future<void> Function(TRPGSession) onPlay;
  final Future<void> Function(TRPGSession) onBackup;
  @override
  State<LocalArchivesScreen> createState() => _LocalArchivesScreenState();
}

class _LocalArchivesScreenState extends State<LocalArchivesScreen> {
  List<TRPGSession> _items = [];
  bool _busy = false;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final items = await widget.repository.getAll(mode: TRPGMode.multiplayer);
    if (mounted) setState(() => _items = items.where((s) => s.metadata['localMultiplayerArchive'] == true).toList());
  }
  Future<void> _action(TRPGSession session, String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (action == 'delete') {
        final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: const Text('删除这份本地记录？'), content: const Text('不会删除原联机房间、云备份或已创建的单人分支。'),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除'))],
        ));
        if (yes == true) await widget.repository.delete(session.id);
      } else if (action == 'solo') {
        final solo = MultiplayerArchiveService.toSolo(session);
        await widget.repository.upsert(solo, onlyIfAbsent: true);
        await widget.onPlay(solo);
      } else if (action == 'backup') {
        await widget.onBackup(session);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已备份到云端')));
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { if (mounted) setState(() => _busy = false); }
  }
  void _read(TRPGSession session) {
    Navigator.push<void>(context, MaterialPageRoute(builder: (c) => Scaffold(
      appBar: AppBar(title: Text(session.title)),
      body: ListView.builder(reverse: true, itemCount: session.chatHistory.length, itemBuilder: (_, i) {
        final message = session.chatHistory[session.chatHistory.length - 1 - i];
        return ListTile(title: SelectableText(message.content), subtitle: Text(message.createdAt.toLocal().toString()));
      }),
    )));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('多人本地存档')),
    body: Column(children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('保存你可见的剧情与角色状态。转为单人会创建独立分支，其他角色由 AI 接手；原联机房间请从多人首页恢复。')),
      if (_busy) const LinearProgressIndicator(),
      Expanded(child: _items.isEmpty ? const Center(child: Text('暂无本地记录，请在房间内点击保存')) : ListView.builder(itemCount: _items.length, itemBuilder: (_, i) {
        final s = _items[i];
        return ListTile(title: Text(s.title), subtitle: Text('${s.chatHistory.length} 条消息 · ${s.updatedAt.toLocal()}'), onTap: () => _read(s),
          trailing: PopupMenuButton<String>(enabled: !_busy, onSelected: (a) => _action(s, a), itemBuilder: (_) => const [
            PopupMenuItem(value: 'solo', child: Text('转为单人并继续')),
            PopupMenuItem(value: 'backup', child: Text('备份云端')),
            PopupMenuItem(value: 'delete', child: Text('删除本地记录')),
          ]));
      })),
    ]),
  );
}
