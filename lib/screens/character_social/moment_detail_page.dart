import 'package:flutter/material.dart';
import '../../models/character_social.dart';
import '../../services/character_social/character_social_service.dart';

class MomentDetailPage extends StatefulWidget {
  const MomentDetailPage({
    super.key,
    required this.post,
    required this.service,
    required this.nameFor,
  });
  final SocialRecord post;
  final CharacterSocialService service;
  final String Function(String) nameFor;
  @override
  State<MomentDetailPage> createState() => _MomentDetailPageState();
}

class _MomentDetailPageState extends State<MomentDetailPage> {
  final _input = TextEditingController();
  List<SocialRecord> _comments = [], _likes = [];
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final comments = await widget.service.repository.list(
      'comment',
      parentId: widget.post.id,
      limit: 100,
    );
    final likes = await widget.service.repository.list(
      'like',
      parentId: widget.post.id,
      limit: 100,
    );
    if (mounted) {
      setState(() {
        _comments = comments;
        _likes = likes;
      });
    }
  }

  Future<void> _comment() async {
    if (_input.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.service.comment(widget.post, _input.text);
      if (mounted) _input.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('动态详情')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.nameFor(widget.post.characterId),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        SelectableText(widget.post.text('content')),
                        const SizedBox(height: 12),
                        Text(
                          _likes.isEmpty
                              ? '暂无点赞'
                              : '${_likes.map((v) => widget.nameFor(v.characterId)).join('、')} 点赞',
                        ),
                      ],
                    ),
                  ),
                ),
                for (final c in _comments.reversed)
                  Card(
                    child: ListTile(
                      title: Text(widget.nameFor(c.characterId)),
                      subtitle: SelectableText(c.text('content')),
                    ),
                  ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_busy,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(hintText: '写评论…'),
                  ),
                ),
                IconButton(
                  tooltip: '发送评论',
                  onPressed: _busy ? null : _comment,
                  icon: const Icon(Icons.send_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
