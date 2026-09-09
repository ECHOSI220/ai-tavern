import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/character.dart';

Future<List<Character>?> showSeedCharacterPickerDialog(
  BuildContext context, {
  required List<Character> characters,
  required List<Character> selected,
}) {
  return showDialog<List<Character>>(
    context: context,
    builder: (_) =>
        _SeedCharacterPickerDialog(characters: characters, selected: selected),
  );
}

class _SeedCharacterPickerDialog extends StatefulWidget {
  const _SeedCharacterPickerDialog({
    required this.characters,
    required this.selected,
  });

  final List<Character> characters;
  final List<Character> selected;

  @override
  State<_SeedCharacterPickerDialog> createState() =>
      _SeedCharacterPickerDialogState();
}

class _SeedCharacterPickerDialogState
    extends State<_SeedCharacterPickerDialog> {
  late final Set<String> _selectedIds = widget.selected
      .map((item) => item.id)
      .toSet();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择世界观核心角色'),
      content: SizedBox(
        width: 620,
        height: 460,
        child: widget.characters.isEmpty
            ? const Center(child: Text('角色卡库为空，请先创建或导入角色卡。'))
            : ListView.builder(
                itemCount: widget.characters.length,
                itemBuilder: (context, index) {
                  final character = widget.characters[index];
                  final avatar = character.avatar;
                  final hasAvatar = avatar != null && File(avatar).existsSync();
                  return CheckboxListTile(
                    value: _selectedIds.contains(character.id),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _selectedIds.add(character.id);
                      } else {
                        _selectedIds.remove(character.id);
                      }
                    }),
                    secondary: CircleAvatar(
                      backgroundImage: hasAvatar
                          ? FileImage(File(avatar))
                          : null,
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
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            widget.characters
                .where((item) => _selectedIds.contains(item.id))
                .toList(),
          ),
          child: Text('使用所选角色（${_selectedIds.length}）'),
        ),
      ],
    );
  }
}
