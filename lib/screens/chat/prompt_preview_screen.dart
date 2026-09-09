import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../models/save_slot.dart';
import '../../services/prompt_builder.dart';

class PromptPreviewScreen extends StatelessWidget {
  const PromptPreviewScreen({
    required this.save,
    required this.settings,
    super.key,
  });

  final SaveSlot save;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final preview = const PromptBuilder().buildSystemPrompt(
      save,
      save.messages,
      settings: settings,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Prompt 预览')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('API Key 不会出现在此预览中。'),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: SelectableText(preview),
            ),
          ),
        ],
      ),
    );
  }
}
