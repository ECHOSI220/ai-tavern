import 'package:flutter/material.dart';

import '../../app/skins/skin_icon.dart';
import '../../models/trpg_models.dart';
import '../../services/trpg/cloud_save_service.dart';

class CloudSavesScreen extends StatefulWidget {
  const CloudSavesScreen({required this.service, super.key});
  final CloudSaveService service;
  @override
  State<CloudSavesScreen> createState() => _CloudSavesScreenState();
}

class _CloudSavesScreenState extends State<CloudSavesScreen> {
  List<Map<String, Object?>> _saves = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _run(() async {
    final saves = await widget.service.list();
    if (mounted) setState(() => _saves = saves);
  });

  Future<void> _upload() => _run(() async {
    final all = await widget.service.repository.getAll();
    final sessions = all.where((s) => s.mode == TRPGMode.solo || s.metadata['localMultiplayerArchive'] == true).toList();
    if (!mounted) return;
    final selected = await showDialog<TRPGSession>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择要备份的存档'),
        content: SizedBox(
          width: 440,
          height: 360,
          child: sessions.isEmpty
              ? const Center(child: Text('本机暂无可备份的存档'))
              : ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(sessions[index].title),
                    subtitle: Text(
                      '更新于 ${sessions[index].updatedAt.toLocal()}',
                    ),
                    onTap: () => Navigator.pop(context, sessions[index]),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await widget.service.upload(selected);
    final saves = await widget.service.list();
    if (mounted) {
      setState(() => _saves = saves);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('云备份已新增，本地进度未改变')));
    }
  });

  Future<void> _restore(Map<String, Object?> save) => _run(() async {
    final title = await widget.service.restore(save['id'].toString());
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已恢复“$title”，请到对应的单人或多人本地存档中打开')));
    }
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('我的云备份'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _busy ? null : _refresh,
          icon: const SkinIcon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '支持单人存档和多人个人记录备份，仅本人可读。恢复不会覆盖已有存档。多人记录可回看或转为单人分支，不会重建原联机房间。显示最近 100 份备份。',
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _upload,
              icon: const SkinIcon(Icons.cloud_upload_outlined),
              label: const Text('备份本机存档'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!_busy && _error == null && _saves.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('还没有云备份')),
            for (final save in _saves)
              Card(
                child: ListTile(
                  leading: const SkinIcon(Icons.cloud_done_outlined),
                  title: Text(save['title']?.toString() ?? '未命名存档'),
                  subtitle: Text(save['description']?.toString() ?? ''),
                  trailing: IconButton(
                    tooltip: '下载到本机',
                    onPressed: _busy ? null : () => _restore(save),
                    icon: const SkinIcon(Icons.download_outlined),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
