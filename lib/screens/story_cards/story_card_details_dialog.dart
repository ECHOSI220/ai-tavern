import 'package:flutter/material.dart';

typedef StoryCardDetails = ({String name, String description, String author});

Future<StoryCardDetails?> showStoryCardDetailsDialog(
  BuildContext context, {
  required String initialName,
  String initialDescription = '',
  String initialAuthor = '',
}) async {
  final name = TextEditingController(text: initialName);
  final description = TextEditingController(text: initialDescription);
  final author = TextEditingController(text: initialAuthor);
  final key = GlobalKey<FormState>();
  final result = await showDialog<StoryCardDetails>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('剧情卡片资料'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: '卡片名称 *'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入卡片名称' : null,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: description,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '卡片简介',
                  hintText: '简要说明题材、开局或特色',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: author,
                decoration: const InputDecoration(labelText: '作者/来源'),
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
        FilledButton(
          onPressed: () {
            if (!key.currentState!.validate()) return;
            Navigator.pop(context, (
              name: name.text.trim(),
              description: description.text.trim(),
              author: author.text.trim(),
            ));
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  name.dispose();
  description.dispose();
  author.dispose();
  return result;
}
