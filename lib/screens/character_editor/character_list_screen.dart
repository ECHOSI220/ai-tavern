import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/character.dart';
import '../../models/save_slot.dart';
import '../../repositories/save_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/export_service.dart';
import 'character_editor_screen.dart';
import '../character_cards/character_card_screen.dart';

class CharacterListScreen extends StatefulWidget {
  const CharacterListScreen({
    required this.save,
    required this.repository,
    required this.characterCardRepository,
    required this.settingsRepository,
    super.key,
  });

  final SaveSlot save;
  final SaveRepository repository;
  final CharacterCardRepository characterCardRepository;
  final SettingsRepository settingsRepository;

  @override
  State<CharacterListScreen> createState() => _CharacterListScreenState();
}

class _CharacterListScreenState extends State<CharacterListScreen> {
  final _exportService = ExportService();
  late SaveSlot _save;

  @override
  void initState() {
    super.initState();
    _save = widget.save;
  }

  Future<void> _persist(List<Character> characters) async {
    final updated = _save.copyWith(
      characters: characters,
      updatedAt: DateTime.now(),
    );
    await widget.repository.upsert(updated);
    if (!mounted) return;
    setState(() => _save = updated);
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
    final list = [..._save.characters];
    final index = list.indexWhere((item) => item.id == result.id);
    if (index < 0) {
      list.add(result);
    } else {
      list[index] = result;
    }
    await _persist(list);
  }

  Future<void> _delete(Character character) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除角色？'),
        content: Text('确认删除“${character.name}”？'),
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
        _save.characters.where((item) => item.id != character.id).toList(),
      );
    }
  }

  Future<void> _import() async {
    try {
      final character = await _exportService.importCharacter();
      if (character == null) return;
      await _persist([..._save.characters, character]);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入角色失败：$error')));
    }
  }

  Future<void> _export(Character character) async {
    try {
      final path = await _exportService.exportCharacter(character);
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('角色已导出：$path')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出角色失败：$error')));
    }
  }

  Future<void> _storeAsCard(Character character) async {
    await widget.characterCardRepository.upsert(character);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('“${character.name}”已收藏到角色卡库')));
  }

  Future<void> _addFromCard() async {
    final character = await Navigator.push<Character>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterCardScreen(
          repository: widget.characterCardRepository,
          settingsRepository: widget.settingsRepository,
          selectForSave: true,
        ),
      ),
    );
    if (character == null) return;
    await _persist([..._save.characters, character]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色管理'),
        actions: [
          IconButton(
            tooltip: '从角色卡库添加',
            onPressed: _addFromCard,
            icon: const Icon(Icons.badge_outlined),
          ),
          IconButton(
            tooltip: '导入角色 JSON',
            onPressed: _import,
            icon: const Icon(Icons.upload_file_outlined),
          ),
        ],
      ),
      body: _save.characters.isEmpty
          ? const Center(child: Text('尚未创建角色'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _save.characters.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final character = _save.characters[index];
                return Card(
                  child: ListTile(
                    onTap: () => _edit(character),
                    leading: CircleAvatar(
                      backgroundImage: character.avatar == null
                          ? null
                          : FileImage(File(character.avatar!)),
                      child: character.avatar == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(character.name),
                    subtitle: Text(
                      character.description.isEmpty
                          ? character.personality
                          : character.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: character.enabled,
                          onChanged: (enabled) {
                            final list = [..._save.characters];
                            list[index] = character.copyWith(enabled: enabled);
                            _persist(list);
                          },
                        ),
                        PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'edit') _edit(character);
                            if (action == 'store') _storeAsCard(character);
                            if (action == 'export') _export(character);
                            if (action == 'delete') _delete(character);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('编辑')),
                            PopupMenuItem(
                              value: 'store',
                              child: Text('收藏为角色卡'),
                            ),
                            PopupMenuItem(
                              value: 'export',
                              child: Text('导出 JSON'),
                            ),
                            PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('新建角色'),
      ),
    );
  }
}
