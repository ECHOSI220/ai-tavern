import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../models/character.dart';
import '../../models/character_social.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../repositories/character_social_repository.dart';
import '../../repositories/save_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/story_card_repository.dart';
import '../../repositories/trpg_session_repository.dart';
import '../../services/character_social/social_import_service.dart';
import '../../services/character_social/social_engine.dart';
import '../../services/character_social/character_social_service.dart';
import '../../services/character_social/social_sync_service.dart';
import '../../services/trpg/account_client_service.dart';
import '../../services/voice/sherpa_text_to_speech_service.dart';
import '../../services/voice/voice_model_manager.dart';
import '../multiplayer_trpg/account_screen.dart';
import '../trpg_shared/trpg_voice_button.dart';
import 'moment_detail_page.dart';

class CharacterSocialScreen extends StatefulWidget {
  const CharacterSocialScreen({
    super.key,
    required this.cards,
    required this.api,
    required this.settings,
    required this.saves,
    required this.stories,
    required this.onExit,
  });
  final CharacterCardRepository cards;
  final ApiRepository api;
  final SettingsRepository settings;
  final SaveRepository saves;
  final StoryCardRepository stories;
  final VoidCallback onExit;
  @override
  State<CharacterSocialScreen> createState() => _CharacterSocialScreenState();
}

class _CharacterSocialScreenState extends State<CharacterSocialScreen>
    with WidgetsBindingObserver {
  late final AccountClientService _account = AccountClientService(
    apiRepository: widget.api,
  );
  CharacterSocialService? _service;
  Timer? _syncTimer;
  bool _foreground = true;
  SocialSyncService? _sync;
  List<SocialRecord> _contacts = [],
      _conversations = [],
      _posts = [],
      _worlds = [];
  Map<String, Character> _cards = {};
  SocialRecord? _prefs;
  int _tab = 0, _feedLimit = 30;
  bool _busy = false, _loading = true;
  String _world = 'default', _search = '', _syncStatus = '本地保存';
  CharacterSocialRepository get repo => _service!.repository;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service?.dispose();
    _syncTimer?.cancel();
    _account.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed && _service != null && !_busy) {
      _run(() async {
        await _service!.catchUp();
        if (_account.tokens != null) await _synchronize();
      });
    }
  }

  Future<void> _start() async {
    _syncTimer?.cancel();
    _service?.dispose();
    if (mounted) {
      setState(() {
        _loading = true;
        _world = 'default';
        _contacts = [];
        _conversations = [];
        _posts = [];
        _cards = {};
      });
    }
    try {
      await _account.restore();
      final repository = CharacterSocialRepository(
        widget.cards.storage,
        owner: _account.tokens?.account.userId ?? 'local',
      );
      _service = CharacterSocialService(
        repository: repository,
        cards: widget.cards,
        api: widget.api,
        settings: widget.settings,
        reserveCloudCall: _account.tokens == null
            ? null
            : (limit) async {
                await _account.supabaseRest(
                  'POST',
                  '/rpc/social_reserve_ai_call',
                  body: {'max_calls': limit},
                );
              },
      );
      _sync = SocialSyncService(repository, _account);
      await _service!.initialize();
      if (_account.tokens != null) {
        try {
          await _synchronize();
        } catch (_) {
          /* keep offline local cache */
        }
        _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          if (mounted && _foreground && !_busy) {
            _backgroundSync();
          }
        });
      }
      await _reload();
      // Cached conversations must be usable before optional AI life simulation
      // finishes; slow providers must not hold the whole page on a spinner.
      if (mounted) setState(() => _loading = false);
      await _service!.catchUp();
      await _reload();
    } catch (e) {
      if (mounted) _notice('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
    } catch (e) {
      _notice('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    final contacts = await repo.list('contact', worldId: _world, limit: 200);
    final conversations = await repo.list(
      'conversation',
      worldId: _world,
      limit: 200,
    );
    final posts = await repo.list('post', worldId: _world, limit: _feedLimit);
    final worlds = await repo.list('world', limit: 100);
    final prefs = await _service!.preferences();
    final cards = <String, Character>{};
    for (final contact in contacts) {
      final c = await _service!.character(contact.characterId);
      if (c != null) cards[c.id] = c;
    }
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _conversations = conversations;
      _posts = posts
          .where(
            (p) => SocialVisibilityFilter.allows(
              p,
              viewer: 'user',
              worldId: _world,
            ),
          )
          .toList();
      _worlds = worlds;
      _prefs = prefs;
      _cards = cards;
    });
  }

  Future<void> _synchronize() async {
    try {
      await _sync!.sync();
      if (mounted) {
        setState(() => _syncStatus = '已同步 ${TimeOfDay.now().format(context)}');
      }
    } catch (e) {
      if (mounted) setState(() => _syncStatus = '同步未完成，本地内容已保留');
      rethrow;
    }
  }

  Future<void> _backgroundSync() async {
    try {
      await _synchronize();
      if (mounted) await _reload();
    } catch (_) {
      /* Offline: no repeated notification toast. */
    }
  }

  String _name(String id) => id == 'user' ? '我' : _cards[id]?.name ?? '角色卡暂不可用';
  Widget _avatar(String id) {
    final path = _cards[id]?.avatar;
    if (path != null && path.startsWith('data:image/jpeg;base64,')) {
      try {
        return CircleAvatar(
          backgroundImage: MemoryImage(
            base64Decode(path.substring('data:image/jpeg;base64,'.length)),
          ),
        );
      } catch (_) {
        return const CircleAvatar(child: Icon(Icons.person_outline));
      }
    }
    return CircleAvatar(
      backgroundImage: path != null && File(path).existsSync()
          ? FileImage(File(path))
          : null,
      child: path == null || !File(path).existsSync()
          ? const Icon(Icons.person_outline)
          : null,
    );
  }

  Future<String?> _input(
    String title, {
    String initial = '',
    int maxLines = 3,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: maxLines,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // Dialog teardown still owns the controller during its exit animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    return result;
  }

  Future<void> _add() async {
    final all = <String, Character>{
      for (final c in await widget.cards.getAll()) c.id: c,
    };
    for (final save in await widget.saves.getAll()) {
      for (final c in save.characters) {
        all.putIfAbsent(c.id, () => c);
      }
    }
    for (final session in await TRPGSessionRepository(
      widget.cards.storage,
    ).getAll()) {
      for (final npc in SocialImportService.knownNpcs(session)) {
        all.putIfAbsent(npc.id, () => npc);
      }
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<Character>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .65,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('选择角色卡 · 包含已有酒馆存档角色'),
              ),
              Expanded(
                child: all.isEmpty
                    ? const Center(child: Text('还没有角色卡，请先在 AI 酒馆中创建或导入。'))
                    : ListView.builder(
                        itemCount: all.length,
                        itemBuilder: (_, i) {
                          final c = all.values.elementAt(i);
                          return ListTile(
                            title: Text(c.name),
                            subtitle: Text(
                              c.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.pop(ctx, c),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await _run(() async {
        await _service!.addCharacter(selected, worldId: _world);
      });
    }
  }

  Future<void> _openChat(SocialRecord conversation) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SocialChatPage(
          service: _service!,
          conversation: conversation,
          names: _cards,
          settings: widget.settings,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _profile(SocialRecord contact) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _ContactPage(
          service: _service!,
          contact: contact,
          card: _cards[contact.characterId],
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _group() async {
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('选择群聊成员'),
          content: SizedBox(
            width: 420,
            height: 300,
            child: ListView(
              children: [
                for (final c in _contacts)
                  CheckboxListTile(
                    title: Text(_name(c.characterId)),
                    value: selected.contains(c.id),
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        selected.add(c.id);
                      } else {
                        selected.remove(c.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: selected.length < 2
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('下一步'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final name = await _input('群聊名称', maxLines: 1);
    if (name == null || name.isEmpty) return;
    await _run(() async {
      await _service!.createGroup(
        name,
        _contacts.where((c) => selected.contains(c.id)).toList(),
      );
    });
  }

  Future<void> _newWorld() async {
    final name = await _input('新建社交世界', maxLines: 1);
    if (name == null || name.isEmpty) return;
    await _run(() async {
      await repo.save(
        SocialRecord.create('world', {
          'name': name,
          'timeMode': 'realTime',
          'publicLore': '',
        }),
      );
    });
  }

  Future<void> _publish() async {
    final text = await _input('发一条朋友圈');
    if (text == null || text.isEmpty || !mounted) return;
    final chosen = <String>{};
    bool all = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('谁可以看到？'),
          content: SizedBox(
            width: 420,
            height: 300,
            child: ListView(
              children: [
                SwitchListTile(
                  title: const Text('当前世界的全部角色'),
                  value: all,
                  onChanged: (v) => setLocal(() => all = v),
                ),
                if (!all)
                  for (final c in _contacts)
                    CheckboxListTile(
                      title: Text(_name(c.characterId)),
                      value: chosen.contains(c.characterId),
                      onChanged: (v) => setLocal(() {
                        if (v == true) {
                          chosen.add(c.characterId);
                        } else {
                          chosen.remove(c.characterId);
                        }
                      }),
                    ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('发布'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(
        () => _service!.publish(
          text,
          _world,
          audience: all ? [] : ['user', ...chosen],
        ),
      );
    }
  }

  Future<void> _worldLore() async {
    final world = await repo.get(_world);
    if (world == null || !mounted) return;
    final text = await _input(
      '该世界允许角色知道的公开资料（不要粘贴 GM 秘密）',
      initial: world.text('publicLore'),
      maxLines: 10,
    );
    if (text != null) {
      await _run(() async {
        await repo.save(world.change({'publicLore': text}));
      });
    }
  }

  Future<void> _importWorldBook() async {
    final stories = await widget.stories.getAll();
    if (!mounted) return;
    final story = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择现有剧情卡的世界书'),
        children: [
          for (final s in stories)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s.id),
              child: Text(s.name),
            ),
        ],
      ),
    );
    if (story == null || !mounted) return;
    final source = stories.firstWhere((s) => s.id == story);
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('仅选择允许社交角色知道的条目'),
          content: SizedBox(
            width: 500,
            height: 350,
            child: ListView(
              children: [
                const Text('默认不共享任何条目。不要勾选 GM 秘密、隐藏剧情或玩家私密资料。'),
                for (final lore in source.template.lorebook.where(
                  (l) => l.enabled,
                ))
                  CheckboxListTile(
                    title: Text(lore.title),
                    subtitle: Text(
                      lore.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: selected.contains(lore.id),
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        selected.add(lore.id);
                      } else {
                        selected.remove(lore.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('批准共享'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final world = await repo.get(_world);
      if (world != null) {
        await repo.save(
          world.change({
            'worldBookId': story,
            'publicLore': source.template.lorebook
                .where((l) => selected.contains(l.id))
                .map((l) => '${l.title}：${l.content}')
                .join('\n'),
          }),
        );
      }
    });
  }

  Future<void> _shareExperiences() async {
    if (_prefs?.flag('sharedMemory') != true) {
      _notice('请先开启跨模式记忆共享；默认隔离。');
      return;
    }
    final contactId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('共享给哪个角色？'),
        children: [
          for (final c in _contacts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c.id),
              child: Text(_name(c.characterId)),
            ),
        ],
      ),
    );
    if (contactId == null) return;
    final contact = _contacts.firstWhere((c) => c.id == contactId);
    final candidates = <SocialRecord>[];
    for (final session in await TRPGSessionRepository(
      widget.cards.storage,
    ).getAll()) {
      final prefix = 'trpg:${session.id}:';
      final actor = contact.characterId.startsWith(prefix)
          ? contact.characterId.substring(prefix.length)
          : contact.characterId;
      for (final memory in session.memoryState.entries) {
        if (SocialImportService.shareable(
          memory,
          actor,
          session.memoryState.knowledgeRelations,
        )) {
          final record = SocialImportService.sharedMemory(contact, memory);
          if (await repo.get(record.id) == null) candidates.add(record);
        }
      }
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      _notice('暂无可共享经历：只允许该角色确实知道的公开已确认记忆，GM秘密始终排除。');
      return;
    }
    final selected = await showDialog<SocialRecord>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择一条已确认经历'),
        children: [
          for (final m in candidates.take(40))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Text(m.text('content')),
            ),
        ],
      ),
    );
    if (selected != null) await _run(() => repo.save(selected));
  }

  Widget _messageList() {
    final rows = _conversations
        .where(
          (c) =>
              (c.text('name').isEmpty ? _name(c.characterId) : c.text('name'))
                  .contains(_search),
        )
        .toList();
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final c = rows[i];
        return Card(
          child: ListTile(
            leading: c.flag('group')
                ? const CircleAvatar(child: Icon(Icons.groups_outlined))
                : _avatar(c.characterId),
            title: Text(
              c.flag('group') ? c.text('name') : _name(c.characterId),
            ),
            trailing: FutureBuilder<int>(
              future: repo.unreadCount(c.id),
              builder: (_, s) => Badge(
                isLabelVisible: (s.data ?? 0) > 0,
                label: Text('${s.data ?? 0}'),
                child: const Icon(Icons.chevron_right),
              ),
            ),
            subtitle: FutureBuilder<List<SocialRecord>>(
              future: repo.list('message', parentId: c.id, limit: 1),
              builder: (_, s) => Text(
                s.data?.firstOrNull?.text('content') ?? '开始聊天',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            onTap: () => _openChat(c),
          ),
        );
      },
    );
  }

  Widget _contactList() {
    final rows = _contacts
        .where(
          (c) =>
              '${_name(c.characterId)} ${c.text('remark')}'.contains(_search),
        )
        .toList();
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final c = rows[i];
        return Card(
          child: ListTile(
            leading: _avatar(c.characterId),
            title: Text(
              c.text('remark').isEmpty
                  ? _name(c.characterId)
                  : c.text('remark'),
            ),
            subtitle: Text(
              (c.data['schedule'] as Map?)?['status'] as String? ?? '离线',
            ),
            onTap: () {
              final conversation = _conversations
                  .where((v) => v.text('contactId') == c.id)
                  .firstOrNull;
              if (conversation != null) _openChat(conversation);
            },
            trailing: IconButton(
              tooltip: '角色档案与记忆',
              icon: const Icon(Icons.info_outline),
              onPressed: () => _profile(c),
            ),
          ),
        );
      },
    );
  }

  Widget _feed() => RefreshIndicator(
    onRefresh: () => _run(() async {
      await _service!.catchUp();
      if (_account.tokens != null) await _synchronize();
    }),
    child: ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _posts.length + 1,
      itemBuilder: (_, i) {
        if (i == _posts.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton(
              onPressed: () => _run(() async {
                _feedLimit = (_feedLimit + 30).clamp(30, 500);
              }),
              child: Text(_posts.isEmpty ? '还没有动态；你可以先发一条。' : '加载更多'),
            ),
          );
        }
        final p = _posts[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _avatar(p.characterId),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_name(p.characterId))),
                    Text(
                      DateTime.fromMillisecondsSinceEpoch(
                        p.createdAt,
                      ).toLocal().toString().substring(5, 16),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(p.text('content')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _run(() => _service!.like(p)),
                      icon: const Icon(Icons.favorite_outline),
                      label: const Text('点赞'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final text = await _input('评论');
                        if (text != null) {
                          await _run(() => _service!.comment(p, text));
                        }
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('评论'),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '动态详情',
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MomentDetailPage(
                              post: p,
                              service: _service!,
                              nameFor: _name,
                            ),
                          ),
                        );
                        if (mounted) await _reload();
                      },
                    ),
                    IconButton(
                      tooltip: '删除动态',
                      onPressed: () =>
                          _run(() => repo.save(p.change({}, deleted: true))),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                FutureBuilder<List<SocialRecord>>(
                  future: repo.list('like', parentId: p.id),
                  builder: (_, s) => Text(
                    (s.data ?? []).map((v) => _name(v.characterId)).join('、'),
                  ),
                ),
                FutureBuilder<List<SocialRecord>>(
                  future: repo.list('comment', parentId: p.id),
                  builder: (_, s) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final comment in (s.data ?? []).reversed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${_name(comment.characterId)}：${comment.text('content')}',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  Widget _settings() {
    final p = _prefs;
    return ListView(
      children: [
        ListTile(
          title: Text(_account.tokens == null ? '本机游客模式' : '账号私人社交空间'),
          subtitle: Text(_syncStatus),
          trailing: TextButton(
            onPressed: () async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => AccountScreen(service: _account),
                ),
              );
              if (mounted) await _start();
            },
            child: const Text('账号'),
          ),
        ),
        ListTile(
          title: const Text('同步联系人、消息、记忆与动态'),
          subtitle: const Text('同账号私人同步，不公开到网页社区'),
          trailing: IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () => _run(_synchronize),
          ),
        ),
        for (final pair in [
          ('autoLife', '自动生活推进'),
          ('autoMoments', '朋友圈自动生成'),
          ('proactive', '角色主动消息'),
          ('instantReply', '立即回复'),
          ('quietHours', '夜间免打扰'),
        ])
          SwitchListTile(
            title: Text(pair.$2),
            value: p?.flag(pair.$1) ?? false,
            onChanged: (v) => _run(() => _service!.configure({pair.$1: v})),
          ),
        ListTile(
          title: const Text('模拟质量'),
          subtitle: const Text('低消耗只推进日程；均衡/丰富按预算生成内容'),
          trailing: DropdownButton<String>(
            value: p?.text('quality', 'lowCost') ?? 'lowCost',
            items: const [
              DropdownMenuItem(value: 'lowCost', child: Text('低消耗')),
              DropdownMenuItem(value: 'balanced', child: Text('均衡')),
              DropdownMenuItem(value: 'rich', child: Text('丰富')),
            ],
            onChanged: (v) => _run(() => _service!.configure({'quality': v})),
          ),
        ),
        ListTile(
          title: const Text('每日自动 AI 调用上限'),
          subtitle: Text('${p?.number('dailyBudget', 12) ?? 12} 次（不含手动聊天）'),
          onTap: () async {
            final value = await _input(
              '每日上限 0–50',
              initial: '${p?.number('dailyBudget', 12) ?? 12}',
              maxLines: 1,
            );
            final n = int.tryParse(value ?? '');
            if (n != null) {
              await _run(
                () => _service!.configure({'dailyBudget': n.clamp(0, 50)}),
              );
            }
          },
        ),
        ListTile(
          title: const Text('新建社交世界'),
          trailing: const Icon(Icons.add),
          onTap: _newWorld,
        ),
        ListTile(
          title: const Text('世界公开资料'),
          subtitle: const Text('只有明确批准的资料才进入社交上下文'),
          onTap: _worldLore,
        ),
        ListTile(title: const Text('从现有世界书选择公开条目'), onTap: _importWorldBook),
        ListTile(
          title: const Text('添加公开世界事件'),
          subtitle: const Text('例如天气、节日或公共活动；只影响当前世界'),
          onTap: () async {
            final text = await _input('公开世界事件');
            if (text != null && text.isNotEmpty) {
              await _run(
                () => repo.save(
                  SocialRecord.create('event', {
                    'content': text,
                    'type': 'WORLD_EVENT',
                    'source': 'user',
                    'visibility': 'PUBLIC_SOCIAL',
                    'importance': 6,
                  }, worldId: _world),
                ),
              );
            }
          },
        ),
        SwitchListTile(
          title: const Text('跨模式记忆共享'),
          subtitle: const Text('默认关闭；开启后仍需逐条批准，GM 隐藏信息不共享'),
          value: p?.flag('sharedMemory') ?? false,
          onChanged: (v) =>
              _run(() => _service!.configure({'sharedMemory': v})),
        ),
        ListTile(title: const Text('选择可共享的跑团经历'), onTap: _shareExperiences),
        ListTile(
          title: const Text('世界时间'),
          trailing: DropdownButton<String>(
            value:
                _worlds
                    .where((w) => w.id == _world)
                    .firstOrNull
                    ?.text('timeMode', 'realTime') ??
                'realTime',
            items: const [
              DropdownMenuItem(value: 'realTime', child: Text('真实时间')),
              DropdownMenuItem(value: 'accelerated', child: Text('加速时间 ×24')),
            ],
            onChanged: (v) => _run(() async {
              final w = await repo.get(_world);
              if (w != null) await repo.save(w.change({'timeMode': v}));
            }),
          ),
        ),
        ListTile(
          title: const Text('同步冲突'),
          subtitle: const Text('发生并发修改时保留双方内容，由你选择'),
          onTap: () async {
            final conflicts = await repo.conflicts();
            if (!mounted) return;
            for (final conflict in conflicts) {
              final local = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('冲突：${conflict.kind}'),
                  content: SingleChildScrollView(
                    child: Text(
                      '本地：${conflict.data}\n\n云端：${conflict.conflict?['payload']}',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('采用云端'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('保留本地'),
                    ),
                  ],
                ),
              );
              if (local != null) {
                await repo.resolveConflict(conflict, keepLocal: local);
              }
              if (!mounted) return;
            }
            if (conflicts.isEmpty) _notice('没有同步冲突');
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['消息', '联系人', '朋友圈', '我的'];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _service == null
        ? const Center(child: Text('初始化失败，请退出重试'))
        : Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_worlds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _world,
                          items: _worlds
                              .map(
                                (w) => DropdownMenuItem(
                                  value: w.id,
                                  child: Text(w.text('name')),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              _run(() async {
                                _world = v;
                              });
                            }
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: '添加联系人',
                        onPressed: _busy ? null : _add,
                        icon: const Icon(Icons.person_add_alt_1),
                      ),
                      IconButton(
                        tooltip: '创建群聊',
                        onPressed: _busy ? null : _group,
                        icon: const Icon(Icons.group_add_outlined),
                      ),
                    ],
                  ),
                ),
              if (_tab < 2)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '搜索联系人或群聊',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
              Expanded(
                child: _contacts.isEmpty && _tab < 2
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '还没有联系人\n从角色卡添加一个角色开始',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _add,
                              child: const Text('选择角色卡'),
                            ),
                          ],
                        ),
                      )
                    : switch (_tab) {
                        0 => _messageList(),
                        1 => _contactList(),
                        2 => _feed(),
                        _ => _settings(),
                      },
              ),
            ],
          );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onExit,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text('角色社交 · ${titles[_tab]}'),
      ),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _tab,
                    onDestinationSelected: (v) => setState(() => _tab = v),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (var i = 0; i < 4; i++)
                        NavigationRailDestination(
                          icon: Icon(
                            [
                              Icons.chat_bubble_outline,
                              Icons.contacts_outlined,
                              Icons.photo_library_outlined,
                              Icons.person_outline,
                            ][i],
                          ),
                          label: Text(titles[i]),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              )
            : body,
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (v) => setState(() => _tab = v),
              destinations: [
                for (var i = 0; i < 4; i++)
                  NavigationDestination(
                    icon: Icon(
                      [
                        Icons.chat_bubble_outline,
                        Icons.contacts_outlined,
                        Icons.photo_library_outlined,
                        Icons.person_outline,
                      ][i],
                    ),
                    label: titles[i],
                  ),
              ],
            ),
      floatingActionButton: _tab == 2
          ? FloatingActionButton(
              tooltip: '发布动态',
              onPressed: _busy
                  ? null
                  : () async {
                      await _publish();
                    },
              child: const Icon(Icons.edit_outlined),
            )
          : null,
    );
  }
}

class SocialChatPage extends StatefulWidget {
  const SocialChatPage({
    super.key,
    required this.service,
    required this.conversation,
    required this.names,
    required this.settings,
  });
  final CharacterSocialService service;
  final SocialRecord conversation;
  final Map<String, Character> names;
  final SettingsRepository settings;
  @override
  State<SocialChatPage> createState() => _SocialChatPageState();
}

class _SocialChatPageState extends State<SocialChatPage> {
  final _input = TextEditingController();
  SherpaTextToSpeechService? _tts;
  SherpaTextToSpeechService get _speech =>
      _tts ??= SherpaTextToSpeechService(VoiceModelManager());
  Timer? _poll;
  List<SocialRecord> _messages = [];
  String? _error;
  String _stream = '', _speaker = '';
  bool _sending = false;
  bool _streamVisible = false;
  int _limit = 40;
  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && !_sending) {
        _load().catchError((Object _) {});
      }
    });
  }

  @override
  void dispose() {
    // The shared social service completes/persists an in-flight reply even if
    // this conversation page is closed. Leaving the whole mode disposes it.
    _poll?.cancel();
    _input.dispose();
    _tts?.dispose();
    super.dispose();
  }

  Future<void> _load({bool finishStream = false}) async {
    final rows = await widget.service.repository.list(
      'message',
      parentId: widget.conversation.id,
      limit: _limit,
    );
    if (mounted) {
      setState(() {
        _messages = rows;
        if (finishStream) {
          _stream = '';
          _streamVisible = false;
        }
      });
    }
    final newest = rows.firstOrNull?.createdAt;
    if (newest != null) {
      final id = 'read:${widget.conversation.id}';
      final old = await widget.service.repository.get(id);
      if (newest > (old?.number('readAt') ?? 0)) {
        await widget.service.repository.save(
          old == null
              ? SocialRecord.create(
                  'read',
                  {'readAt': newest},
                  id: id,
                  parentId: widget.conversation.id,
                  worldId: widget.conversation.worldId,
                )
              : old.change({'readAt': newest}),
        );
      }
    }
  }

  Future<void> _send({bool retry = false}) async {
    final text = retry
        ? _messages
                  .where((m) => m.text('sender') == 'user')
                  .firstOrNull
                  ?.text('content') ??
              ''
        : _input.text;
    if (text.trim().isEmpty) return;
    setState(() {
      _sending = true;
      _streamVisible = true;
      _error = null;
      _stream = '';
    });
    try {
      await widget.service.send(
        widget.conversation,
        text,
        retryId: retry ? 'retry' : null,
        deferMemory: true,
        onMessageSaved: (isReply) async {
          if (!mounted) return;
          if (!retry && !isReply) _input.clear();
          await _load(finishStream: isReply);
        },
        onChunk: (id, chunk) {
          if (mounted) {
            setState(() {
              _speaker = id;
              _stream = chunk;
              _streamVisible = true;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        await _load();
        if (mounted) {
          setState(() {
            _sending = false;
            _streamVisible = false;
            _stream = '';
          });
        }
      }
    }
  }

  Future<void> _speak(SocialRecord m) async {
    try {
      final s = await widget.settings.load();
      await _speech.speak(
        m.text('content'),
        voice: s.voiceSettings.voiceFor(m.characterId),
        messageId: m.id,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('朗读失败：$e')));
      }
    }
  }

  Future<void> _clear() async {
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理本次聊天'),
        content: const Text('是否同时删除从这次聊天提取的共同记忆？不会重置角色关系与状态。删除会同步到同账号设备。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: const Text('只删除聊天'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 2),
            child: const Text('聊天和相关记忆'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await widget.service.clearConversation(
      widget.conversation,
      clearMemories: choice == 2,
    );
    await _load();
  }

  Widget _bubble({
    Key? key,
    required String content,
    required String name,
    bool user = false,
    VoidCallback? onSpeak,
  }) => Align(
    key: key,
    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Card(
        color: user ? Theme.of(context).colorScheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.labelSmall),
              SelectableText(content),
              if (!user)
                IconButton(
                  tooltip: '朗读',
                  onPressed: onSpeak,
                  icon: const Icon(Icons.volume_up_outlined),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        IconButton(
          tooltip: '清理聊天记录',
          onPressed: _sending ? null : _clear,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
      title: Text(
        widget.conversation.flag('group')
            ? widget.conversation.text('name')
            : widget.names[widget.conversation.characterId]?.name ?? '私聊',
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + 1 + (_streamVisible ? 1 : 0),
              itemBuilder: (_, i) {
                if (_streamVisible && i == 0) {
                  return _bubble(
                    key: const ValueKey('social-stream'),
                    content: _stream.isEmpty ? '正在输入…' : _stream,
                    name:
                        widget.names[_speaker]?.name ??
                        widget.names[widget.conversation.characterId]?.name ??
                        '角色',
                  );
                }
                final index = i - (_streamVisible ? 1 : 0);
                if (index == _messages.length) {
                  return TextButton(
                    onPressed: () async {
                      _limit = (_limit + 40).clamp(40, 500);
                      await _load();
                    },
                    child: const Text('加载更早消息'),
                  );
                }
                final m = _messages[index];
                final user = m.text('sender') == 'user';
                return _bubble(
                  key: ValueKey(m.id),
                  content: m.text('content'),
                  name: user ? '我' : widget.names[m.characterId]?.name ?? '角色',
                  user: user,
                  onSpeak: user ? null : () => _speak(m),
                );
              },
            ),
          ),
          if (_error != null)
            ListTile(
              title: Text(_error!),
              trailing: TextButton(
                onPressed: _sending ? null : () => _send(retry: true),
                child: const Text('重试回复'),
              ),
            ),
          Card(
            margin: const EdgeInsets.all(10),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TrpgVoiceButton(
                    controller: _input,
                    settingsRepository: widget.settings,
                    enabled: !_sending,
                    onStart: () async {
                      await _tts?.stop();
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: '发消息…',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '发送',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_outlined),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ContactPage extends StatefulWidget {
  const _ContactPage({
    required this.service,
    required this.contact,
    required this.card,
  });
  final CharacterSocialService service;
  final SocialRecord contact;
  final Character? card;
  @override
  State<_ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<_ContactPage> {
  late String _remark = widget.contact.text('remark');
  List<SocialRecord> _memories = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await widget.service.repository.list(
      'memory',
      characterId: widget.contact.characterId,
      worldId: widget.contact.worldId,
      limit: 100,
    );
    if (mounted) setState(() => _memories = m);
  }

  Future<void> _edit(SocialRecord memory) async {
    final controller = TextEditingController(text: memory.text('content'));
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修正记忆'),
        content: TextField(controller: controller, maxLines: 5),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (text != null) {
      await widget.service.repository.save(
        memory.change({'content': text, 'userCorrected': true}),
      );
    }
    await _load();
  }

  Future<void> _editRemark() async {
    final input = TextEditingController(text: _remark);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('联系人备注（不改变角色自我认知）'),
        content: TextField(controller: input, maxLength: 40),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null) return;
    final current = await widget.service.repository.get(widget.contact.id);
    if (current == null) return;
    await widget.service.repository.save(current.change({'remark': value}));
    if (mounted) setState(() => _remark = value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.card?.name ?? '角色档案')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '关系：${SocialRelationshipState.label((widget.contact.data['relationship'] as Map? ?? {}).cast<String, Object?>())}',
                ),
                Text(
                  '心情：${(widget.contact.data['mood'] as Map?)?['primaryMood'] ?? '平静'}',
                ),
                Text(
                  '状态：${(widget.contact.data['schedule'] as Map?)?['activity'] ?? '暂无活动'}',
                ),
                const Text('角色人格随原角色卡更新；共同记忆不会重置。'),
              ],
            ),
          ),
        ),
        ListTile(
          title: const Text('联系人备注'),
          subtitle: Text(_remark.isEmpty ? '未设置' : _remark),
          onTap: _editRemark,
        ),
        Text('共同记忆', style: Theme.of(context).textTheme.titleLarge),
        if (_memories.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('还没有重要共同记忆。普通闲聊不会全部永久记住。'),
          ),
        for (final m in _memories)
          Card(
            child: ListTile(
              title: Text(m.text('content')),
              onTap: () => _edit(m),
              trailing: IconButton(
                tooltip: '删除错误记忆',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await widget.service.repository.save(
                    m.change({}, deleted: true),
                  );
                  await _load();
                },
              ),
            ),
          ),
      ],
    ),
  );
}
