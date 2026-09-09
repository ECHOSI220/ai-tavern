import 'dart:io';

import 'package:flutter/material.dart';

import '../models/save_slot.dart';

enum SaveAction { edit, aiExpandWorld, storeAsCard, duplicate, export, delete }

class SaveCard extends StatelessWidget {
  const SaveCard({
    required this.save,
    required this.onOpen,
    required this.onAction,
    super.key,
  });

  final SaveSlot save;
  final VoidCallback onOpen;
  final ValueChanged<SaveAction> onAction;

  String get _characterNames {
    final names = save.characters.map((item) => item.name).take(3).join(' / ');
    return names.isEmpty ? '尚未创建角色' : names;
  }

  String get _lastPlayed {
    final now = DateTime.now();
    final date = save.lastPlayedAt;
    if (now.year == date.year &&
        now.month == date.month &&
        now.day == date.day) {
      return '今天 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _showDesktopMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {
    final action = await showMenu<SaveAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: SaveAction.edit, child: Text('编辑')),
        PopupMenuItem(value: SaveAction.aiExpandWorld, child: Text('AI 拓展世界观')),
        PopupMenuItem(value: SaveAction.storeAsCard, child: Text('收藏为剧情卡片')),
        PopupMenuItem(value: SaveAction.duplicate, child: Text('复制存档')),
        PopupMenuItem(value: SaveAction.export, child: Text('导出 JSON')),
        PopupMenuItem(value: SaveAction.delete, child: Text('删除')),
      ],
    );
    if (action != null) onAction(action);
  }

  Future<void> _showMobileMenu(BuildContext context) async {
    final action = await showModalBottomSheet<SaveAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(context, SaveAction.edit),
            ),
            ListTile(
              leading: const Icon(Icons.public_outlined),
              title: const Text('AI 拓展世界观'),
              subtitle: const Text('追加世界设定，不改变游玩进度'),
              onTap: () => Navigator.pop(context, SaveAction.aiExpandWorld),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制存档'),
              onTap: () => Navigator.pop(context, SaveAction.duplicate),
            ),
            ListTile(
              leading: const Icon(Icons.add_card_outlined),
              title: const Text('收藏为剧情卡片'),
              onTap: () => Navigator.pop(context, SaveAction.storeAsCard),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('导出 JSON'),
              onTap: () => Navigator.pop(context, SaveAction.export),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () => Navigator.pop(context, SaveAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action != null) onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) => _showDesktopMenu(context, details),
      onLongPress: () => _showMobileMenu(context),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundImage:
                          save.coverImage != null &&
                              File(save.coverImage!).existsSync()
                          ? FileImage(File(save.coverImage!))
                          : null,
                      child:
                          save.coverImage == null ||
                              !File(save.coverImage!).existsSync()
                          ? const Icon(Icons.local_fire_department_outlined)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        save.name,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    PopupMenuButton<SaveAction>(
                      tooltip: '存档操作',
                      onSelected: onAction,
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: SaveAction.edit,
                          child: Text('编辑'),
                        ),
                        PopupMenuItem(
                          value: SaveAction.aiExpandWorld,
                          child: Text('AI 拓展世界观'),
                        ),
                        PopupMenuItem(
                          value: SaveAction.storeAsCard,
                          child: Text('收藏为剧情卡片'),
                        ),
                        PopupMenuItem(
                          value: SaveAction.duplicate,
                          child: Text('复制存档'),
                        ),
                        PopupMenuItem(
                          value: SaveAction.export,
                          child: Text('导出 JSON'),
                        ),
                        PopupMenuItem(
                          value: SaveAction.delete,
                          child: Text('删除'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _characterNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Row(
                  children: [
                    Text('${save.messageCount} 条消息'),
                    const Spacer(),
                    Text('最后游玩：$_lastPlayed'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
