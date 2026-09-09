import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/community_links.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../repositories/story_card_repository.dart';
import '../../services/cloud_share_service.dart';
import '../../services/trpg/account_client_service.dart';
import '../multiplayer_trpg/account_screen.dart';

class CloudUploadScreen extends StatefulWidget {
  const CloudUploadScreen({
    required this.apiRepository,
    required this.characters,
    required this.stories,
    super.key,
  });
  final ApiRepository apiRepository;
  final CharacterCardRepository characters;
  final StoryCardRepository stories;
  @override
  State<CloudUploadScreen> createState() => _CloudUploadScreenState();
}

class _UploadItem {
  const _UploadItem(this.title, this.kind, this.package);
  final String title, kind;
  final Map<String, Object?> package;
}

class _CloudUploadScreenState extends State<CloudUploadScreen> {
  late final AccountClientService _account;
  late final CloudShareService _service;
  late final Future<List<_UploadItem>> _items;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _account = AccountClientService(apiRepository: widget.apiRepository);
    _service = CloudShareService(_account);
    _items = _load();
  }

  Future<List<_UploadItem>> _load() async => [
    for (final c in await widget.characters.getAll())
      _UploadItem(c.name, '角色卡', CloudShareService.characterPackage(c)),
    for (final s in await widget.stories.getAll())
      _UploadItem(s.name, '剧情模板', CloudShareService.storyPackage(s)),
  ];
  @override
  void dispose() {
    _service.dispose();
    _account.dispose();
    super.dispose();
  }

  Future<void> _upload(_UploadItem item) async {
    setState(() => _busy = true);
    try {
      await _account.restore();
      if (!mounted) return;
      if (_account.tokens == null) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => AccountScreen(service: _account)),
        );
      }
      if (!mounted || _account.tokens == null) return;
      String visibility = 'PRIVATE';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text('上传「${item.title}」'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '仅上传下方预览中的创作设定；不上传聊天记录、记忆、角色秘密、账号密钥或本地图片。请确认你拥有分享权限，并检查文字中是否有隐私。',
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: visibility,
                      items: const [
                        DropdownMenuItem(
                          value: 'PRIVATE',
                          child: Text('仅自己可见'),
                        ),
                        DropdownMenuItem(
                          value: 'UNLISTED',
                          child: Text('仅分享链接可见'),
                        ),
                        DropdownMenuItem(
                          value: 'PUBLIC',
                          child: Text('公开到网页发现页'),
                        ),
                      ],
                      onChanged: (value) => setLocal(() => visibility = value!),
                    ),
                    const SizedBox(height: 12),
                    ExpansionTile(
                      title: const Text('查看实际上传内容'),
                      children: [
                        SelectableText(
                          const JsonEncoder.withIndent(
                            '  ',
                          ).convert(item.package),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认上传'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
      final link = await _service.upload(
        package: item.package,
        title: item.title,
        description: '从 AI 酒馆分享的${item.kind}',
        visibility: visibility,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('已上传到 Tavern Cloud'),
          content: SelectableText(link),
          actions: [
            TextButton(
              onPressed: () =>
                  openCommunityWebsite(context, path: Uri.parse(link).path),
              child: const Text('打开网页／添加封面'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('复制链接'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('上传未完成：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('快捷上传 · 云端社区')),
      body: FutureBuilder<List<_UploadItem>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('读取本地创作失败，请返回重试'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const CommunityLinks(),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '选择角色卡或剧情模板，确认后即可上传。使用与网页相同的账号；私人存档和聊天不会自动公开。',
                      ),
                    ),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('还没有可上传的角色卡或剧情卡，请先到对应卡片库创建。'),
                    ),
                  for (final item in items)
                    Card(
                      child: ListTile(
                        title: Text(item.title),
                        subtitle: Text(item.kind),
                        trailing: IconButton(
                          tooltip: '上传到网页',
                          icon: const Icon(Icons.cloud_upload_outlined),
                          onPressed: _busy ? null : () => _upload(item),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
