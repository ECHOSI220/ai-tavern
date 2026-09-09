import '../app/skins/skin_icon.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../app/skins/themed_components.dart';
import '../app/skins/theme_craft.dart';
import '../app/skins/theme_tokens.dart';
import '../app/skins/character_theme.dart';

enum MessageAction { copy, edit, delete, regenerate, continueFrom }

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.isStreaming,
    required this.onAction,
    required this.onRetry,
    this.onSpeak,
    this.isSpeaking = false,
    this.isSpeechLoading = false,
    this.onRetryVision,
    this.showVisionDebug = false,
    super.key,
  });

  final ChatMessage message;
  final bool isStreaming;
  final ValueChanged<MessageAction> onAction;
  final VoidCallback onRetry;
  final VoidCallback? onSpeak;
  final bool isSpeaking;
  final bool isSpeechLoading;
  final VoidCallback? onRetryVision;
  final bool showVisionDebug;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制消息')));
    }
  }

  List<PopupMenuEntry<MessageAction>> _actions() => [
    const PopupMenuItem(value: MessageAction.copy, child: Text('复制')),
    const PopupMenuItem(value: MessageAction.edit, child: Text('编辑')),
    const PopupMenuItem(value: MessageAction.delete, child: Text('删除')),
    if (message.role == ChatRole.assistant)
      const PopupMenuItem(value: MessageAction.regenerate, child: Text('重新生成')),
    const PopupMenuItem(
      value: MessageAction.continueFrom,
      child: Text('从这里继续'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ThemedMessageContent(
      light: message.role == ChatRole.assistant,
      builder: _buildContent,
    );
  }

  Widget _buildContent(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final craft = SkinCraft.of(context);
    final kind = isUser ? ChatBubbleKind.user : ChatBubbleKind.ai;
    final background = ThemedChatBubble.background(context, kind);
    final foreground = ThemedChatBubble.foreground(context, kind);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Card(
          color: background,
          child: Padding(
            padding: craft.refined
                ? const EdgeInsets.fromLTRB(20, 14, 12, 20)
                : const EdgeInsets.fromLTRB(16, 12, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SkinIcon(
                      isUser ? Icons.person_outline : Icons.auto_awesome,
                      size: 17,
                      color: craft.refined ? craft.accent : null,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      isUser ? '玩家' : 'AI 剧情',
                      style: craft.refined
                          ? Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: craft.accent,
                              letterSpacing: .7,
                            )
                          : null,
                    ),
                    const Spacer(),
                    if (!isUser && message.content.trim().isNotEmpty)
                      IconButton(
                        tooltip: isSpeaking ? '停止朗读' : '朗读消息',
                        onPressed: isSpeechLoading ? null : onSpeak,
                        icon: isSpeechLoading
                            ? const SizedBox.square(
                                dimension: 17,
                                child: ThemedLoadingIndicator(strokeWidth: 2),
                              )
                            : SkinIcon(
                                isSpeaking
                                    ? Icons.stop_circle_outlined
                                    : Icons.volume_up_outlined,
                              ),
                      ),
                    PopupMenuButton<MessageAction>(
                      tooltip: '消息操作',
                      onSelected: (action) {
                        if (action == MessageAction.copy) {
                          _copy(context);
                        } else {
                          onAction(action);
                        }
                      },
                      itemBuilder: (_) => _actions(),
                    ),
                  ],
                ),
                if (craft.refined)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Divider(
                      height: 1,
                      color: ThemeTokens.of(context).borderSecondary,
                    ),
                  ),
                if (message.attachments.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: message.attachments
                        .map(
                          (attachment) => _imageAttachment(context, attachment),
                        )
                        .toList(),
                  ),
                ],
                if (message.content.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      top: message.attachments.isEmpty ? 0 : 10,
                    ),
                    child: MarkdownBody(
                      data: message.content,
                      selectable: true,
                      styleSheet: craft.refined
                          ? MarkdownStyleSheet(
                              p: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: foreground, height: 1.75),
                              blockSpacing: 16,
                            )
                          : null,
                    ),
                  ),
                if (showVisionDebug &&
                    (message.visionContext?.trim().isNotEmpty ?? false))
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('查看识图摘要'),
                    children: [SelectableText(message.visionContext!)],
                  ),
                if (isStreaming)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox.square(
                          dimension: 14,
                          child: ThemedLoadingIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '正在生成……',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                if (message.isInterrupted)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('■ 已停止生成'),
                  ),
                if (message.errorMessage case final error?)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('⚠ AI 生成失败\n$error'),
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: onRetry,
                          icon: const SkinIcon(Icons.refresh),
                          label: const Text('重新生成'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _imageAttachment(BuildContext context, ChatAttachment attachment) {
    final file = File(attachment.localPath);
    final status = attachment.analysisStatus;
    final analyzing =
        status == AttachmentAnalysisStatus.analyzing ||
        status == AttachmentAnalysisStatus.pending;
    final failed = status == AttachmentAnalysisStatus.error;
    return SizedBox(
      width: 168,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: file.existsSync()
                  ? Image.file(file, fit: BoxFit.cover)
                  : ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: const Center(child: SkinIcon(Icons.broken_image)),
                    ),
            ),
          ),
          if (analyzing)
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 13,
                    child: ThemedLoadingIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 6),
                  Text('正在分析图片……', style: TextStyle(fontSize: 12)),
                ],
              ),
            )
          else if (failed)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (attachment.errorMessage?.trim().isNotEmpty ?? false)
                    Text(
                      attachment.errorMessage!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 11,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: onRetryVision,
                    icon: const SkinIcon(Icons.refresh, size: 16),
                    label: const Text('分析失败，重试'),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                children: [
                  SkinIcon(
                    Icons.visibility_outlined,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 5),
                  const Text('已识图', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
