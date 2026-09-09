import 'package:flutter/material.dart';

import '../../models/player_reply_tone.dart';

Future<PlayerReplyToneSelection?> showPlayerReplyToneDialog(
  BuildContext context, {
  required PlayerReplyTone initialTone,
}) {
  return showDialog<PlayerReplyToneSelection>(
    context: context,
    builder: (_) => _PlayerReplyToneDialog(initialTone: initialTone),
  );
}

class _PlayerReplyToneDialog extends StatefulWidget {
  const _PlayerReplyToneDialog({required this.initialTone});

  final PlayerReplyTone initialTone;

  @override
  State<_PlayerReplyToneDialog> createState() => _PlayerReplyToneDialogState();
}

class _PlayerReplyToneDialogState extends State<_PlayerReplyToneDialog> {
  late PlayerReplyTone _tone = widget.initialTone;
  final _customTone = TextEditingController();

  @override
  void dispose() {
    _customTone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.psychology_alt_outlined),
          SizedBox(width: 10),
          Text('选择思考语气'),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('AI 会结合当前世界观和对话，替玩家构思下一段输入，但不会自动发送。'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PlayerReplyTone.values
                    .map(
                      (tone) => ChoiceChip(
                        label: Text(tone.label),
                        selected: tone == _tone,
                        onSelected: (_) => setState(() => _tone = tone),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('${_tone.label}：${_tone.instruction}'),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _customTone,
                maxLength: 80,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '自定义语气补充（可选）',
                  hintText: '例如：表面冷酷，但其实很担心对方',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            PlayerReplyToneSelection(
              tone: _tone,
              customTone: _customTone.text.trim(),
            ),
          ),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('开始思考'),
        ),
      ],
    );
  }
}
