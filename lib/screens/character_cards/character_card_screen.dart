import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/character.dart';
import '../../models/campaign_models.dart';
import '../../repositories/campaign_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/export_service.dart';
import '../character_editor/character_editor_screen.dart';
import '../character_social/add_social_contact.dart';

class CharacterCardScreen extends StatefulWidget {
  const CharacterCardScreen({
    required this.repository,
    required this.settingsRepository,
    this.campaignRepository,
    this.selectForSave = false,
    super.key,
  });

  final CharacterCardRepository repository;
  final SettingsRepository settingsRepository;
  final CampaignRepository? campaignRepository;
  final bool selectForSave;

  @override
  State<CharacterCardScreen> createState() => _CharacterCardScreenState();
}

class _CharacterCardScreenState extends State<CharacterCardScreen> {
  final _exportService = ExportService();
  var _loading = true;
  List<Character> _cards = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cards = await widget.repository.getAll();
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _loading = false;
    });
  }

  Future<void> _edit([Character? character]) async {
    final result = await Navigator.push<Character>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterEditorScreen(
          initialCharacter: character,
          settingsRepository: widget.settingsRepository,
        ),
      ),
    );
    if (result == null) return;
    await widget.repository.upsert(result);
    await _load();
  }

  Future<void> _import() async {
    try {
      final character = await _exportService.importCharacter();
      if (character == null) return;
      await widget.repository.upsert(character);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入角色卡失败：$error')));
    }
  }

  Future<void> _export(Character character) async {
    try {
      final path = await _exportService.exportCharacter(character);
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('角色卡已导出：$path')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出角色卡失败：$error')));
    }
  }

  Future<void> _delete(Character character) async {
    final referenced = await widget.repository.hasSocialReferences(
      character.id,
    );
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除角色卡？'),
        content: Text(
          referenced
              ? '“${character.name}”仍在角色社交中使用。删除原卡时保留当前人格快照、关系与共同记忆。'
              : '只会删除卡片库中的“${character.name}”，不影响已加入存档的角色。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(referenced ? '保留快照并删除原卡' : '删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.delete(
      character.id,
      preserveSocialSnapshot: referenced,
    );
    await _load();
  }

  void _use(Character character) {
    Navigator.pop(context, character.copyWith(id: const Uuid().v4()));
  }

  Future<void> _useForTrpg(Character character) async {
    final repository = widget.campaignRepository;
    if (repository == null) return;
    final campaigns = await repository.getAll();
    if (!mounted) return;
    if (campaigns.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在跑团模式的剧本库中新建剧本')));
      return;
    }
    CampaignNpcRole role = CampaignNpcRole.npc;
    CampaignDocument selected = campaigns.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('将“${character.name}”用于跑团'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<CampaignDocument>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: '目标剧本'),
                  items: campaigns
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.title),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setLocal(() => selected = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CampaignNpcRole>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: '用途'),
                  items: CampaignNpcRole.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setLocal(() => role = value!),
                ),
                const SizedBox(height: 10),
                const Text(
                  '只建立 sourceCharacterId 引用并复制人设快照；跑团中的 HP、物品、关系和记忆不会修改原角色卡。',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('添加到跑团'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final profile = TRPGNPCProfile.fromCharacter(character, role: role);
    await repository.upsert(
      selected.copyWith(npcs: [...selected.npcs, profile]),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已作为 ${role.name} 添加到“${selected.title}”')),
      );
    }
  }

  Widget _item(Character character) {
    final avatar = character.avatar;
    final hasAvatar = avatar != null && File(avatar).existsSync();
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        onTap: widget.selectForSave
            ? () => _use(character)
            : () => _edit(character),
        leading: CircleAvatar(
          radius: 28,
          backgroundImage: hasAvatar ? FileImage(File(avatar)) : null,
          child: hasAvatar ? null : const Icon(Icons.person),
        ),
        title: Text(character.name),
        subtitle: Text(
          character.description.isEmpty
              ? character.personality
              : character.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: widget.selectForSave
            ? FilledButton(
                onPressed: () => _use(character),
                child: const Text('添加'),
              )
            : PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'edit') _edit(character);
                  if (action == 'social') {
                    addSocialContact(
                      context,
                      character,
                      widget.repository,
                      widget.settingsRepository,
                    );
                  }
                  if (action == 'export') _export(character);
                  if (action == 'trpg') _useForTrpg(character);
                  if (action == 'delete') _delete(character);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('编辑角色卡')),
                  const PopupMenuItem(value: 'social', child: Text('添加到角色社交')),
                  const PopupMenuItem(value: 'export', child: Text('导出 JSON')),
                  if (widget.campaignRepository != null)
                    const PopupMenuItem(value: 'trpg', child: Text('用于跑团')),
                  const PopupMenuItem(value: 'delete', child: Text('删除角色卡')),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectForSave ? '从角色卡库添加' : '角色卡库'),
        actions: [
          IconButton(
            tooltip: '导入角色卡 JSON',
            onPressed: _import,
            icon: const Icon(Icons.upload_file),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cards.isEmpty
          ? const Center(child: Text('角色卡库还是空的，可以新建或导入角色卡。'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _cards.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) => _item(_cards[index]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('新建角色卡'),
      ),
    );
  }
}
