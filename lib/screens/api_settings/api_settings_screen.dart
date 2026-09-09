import 'package:flutter/material.dart';

import '../../models/api_profile.dart';
import '../../models/app_settings.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import 'api_profile_editor_screen.dart';

class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({
    required this.apiRepository,
    required this.settingsRepository,
    required this.aiService,
    super.key,
  });

  final ApiRepository apiRepository;
  final SettingsRepository settingsRepository;
  final AiService aiService;

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  var _loading = true;
  List<ApiProfile> _profiles = const [];
  AppSettings _settings = const AppSettings();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profiles = await widget.apiRepository.getAll();
    final settings = await widget.settingsRepository.load();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _edit([ApiProfile? profile]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ApiProfileEditorScreen(
          repository: widget.apiRepository,
          aiService: widget.aiService,
          initialProfile: profile,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _makeDefault(ApiProfile profile) async {
    final updated = _settings.copyWith(defaultApiProfileId: profile.id);
    await widget.settingsRepository.save(updated);
    if (mounted) setState(() => _settings = updated);
  }

  Future<void> _delete(ApiProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 API 配置？'),
        content: Text('“${profile.name}”及其本地密钥将被删除。'),
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
    await widget.apiRepository.delete(profile.id);
    if (_settings.defaultApiProfileId == profile.id) {
      _settings = _settings.copyWith(defaultApiProfileId: '');
      await widget.settingsRepository.save(_settings);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI API')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
          ? const Center(child: Text('尚未创建 API 配置'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _profiles.length,
              itemBuilder: (context, index) {
                final profile = _profiles[index];
                final isDefault = profile.id == _settings.defaultApiProfileId;
                return Card(
                  child: ListTile(
                    onTap: () => _edit(profile),
                    leading: Icon(isDefault ? Icons.star : Icons.hub_outlined),
                    title: Text(profile.name),
                    subtitle: Text('${profile.model}\n${profile.baseUrl}'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'default') _makeDefault(profile);
                        if (action == 'edit') _edit(profile);
                        if (action == 'delete') _delete(profile);
                      },
                      itemBuilder: (_) => [
                        if (!isDefault)
                          const PopupMenuItem(
                            value: 'default',
                            child: Text('设为默认'),
                          ),
                        const PopupMenuItem(value: 'edit', child: Text('编辑')),
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('新建 API 配置'),
      ),
    );
  }
}
