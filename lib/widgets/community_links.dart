import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cloud_share_service.dart';

Future<void> openCommunityWebsite(
  BuildContext context, {
  String path = '/discover',
}) async {
  final uri = Uri.parse('${CloudShareService.website}$path');
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // Keep the link accessible even when no browser can handle it.
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('请在浏览器中打开'),
      content: SelectableText(uri.toString()),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: uri.toString()));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: const Text('复制网址'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class CommunityLinks extends StatelessWidget {
  const CommunityLinks({super.key});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('酒馆网页社区', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('发现创作、分享 JSON，为已上传作品添加或更换封面。网页使用同一邮箱账号登录。'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => openCommunityWebsite(context),
                icon: const Icon(Icons.open_in_new),
                label: const Text('打开网页社区'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    openCommunityWebsite(context, path: '/me/uploads'),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('网页我的创作'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
