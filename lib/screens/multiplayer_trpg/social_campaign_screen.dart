import 'package:flutter/material.dart';

import '../../models/social_models.dart';
import '../../services/trpg/account_client_service.dart';

class SocialCampaignScreen extends StatefulWidget {
  const SocialCampaignScreen({
    required this.service,
    required this.account,
    required this.onContinue,
    super.key,
  });
  final AccountClientService service;
  final UserAccount account;
  final Future<void> Function(PersistentCampaignRoom room) onContinue;
  @override
  State<SocialCampaignScreen> createState() => _SocialCampaignScreenState();
}

class _SocialCampaignScreenState extends State<SocialCampaignScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final _handle = TextEditingController();
  final _title = TextEditingController(text: '雾港长期团');
  List<PersistentCampaignRoom> _campaigns = const [];
  List<Map<String, Object?>> _friends = const [];
  List<SocialInvite> _invites = const [];
  List<CampaignNotification> _notifications = const [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final values = await Future.wait([
        widget.service.get('/api/campaigns'),
        widget.service.get('/api/friends'),
        widget.service.get('/api/invites'),
        widget.service.get('/api/notifications'),
      ]);
      if (!mounted) return;
      setState(() {
        _campaigns = (values[0]['campaigns'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (value) => PersistentCampaignRoom.fromJson(
                value.cast<String, Object?>(),
              ),
            )
            .toList();
        _friends = (values[1]['friends'] as List? ?? const [])
            .whereType<Map>()
            .map((value) => value.cast<String, Object?>())
            .toList();
        _invites = (values[2]['invites'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (value) => SocialInvite.fromJson(value.cast<String, Object?>()),
            )
            .toList();
        _notifications = (values[3]['notifications'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (value) =>
                  CampaignNotification.fromJson(value.cast<String, Object?>()),
            )
            .toList();
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.account.displayName),
          Text(
            '@${widget.account.handle}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
      bottom: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabs: const [
          Tab(text: '我的战役'),
          Tab(text: '好友'),
          Tab(text: '邀请'),
          Tab(text: '通知'),
        ],
      ),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    body: _busy
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : TabBarView(
            controller: _tabs,
            children: [
              _campaignList(),
              _friendList(),
              _inviteList(),
              _notificationList(),
            ],
          ),
  );

  Widget _campaignList() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      FilledButton.icon(
        onPressed: _createCampaign,
        icon: const Icon(Icons.add),
        label: const Text('创建永久战役'),
      ),
      ..._campaigns.map(
        (room) => Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.auto_stories)),
            title: Text(room.title),
            subtitle: Text(
              '第 ${room.revision} 版 · ${room.members.length}/${room.maxMembers} 人\n'
              '${room.announcement.isEmpty ? '暂无公告' : room.announcement}',
            ),
            isThreeLine: true,
            trailing: Text(room.lifecycle.name),
            onTap: () => _showHub(room),
          ),
        ),
      ),
    ],
  );

  Widget _friendList() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      TextField(
        controller: _handle,
        decoration: InputDecoration(
          labelText: '通过用户 ID 添加好友',
          prefixText: '@',
          suffixIcon: IconButton(
            onPressed: _requestFriend,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ),
      ),
      ..._friends.map((entry) {
        final account = UserAccount.fromJson(
          (entry['account'] as Map).cast<String, Object?>(),
        );
        final friendship = Friendship.fromJson(
          (entry['friendship'] as Map).cast<String, Object?>(),
        );
        final incoming =
            friendship.status == FriendshipStatus.pending &&
            friendship.addresseeUserId == widget.account.userId;
        return ListTile(
          leading: CircleAvatar(
            child: Text(account.displayName.characters.firstOrNull ?? '?'),
          ),
          title: Text(account.displayName),
          subtitle: Text('@${account.handle} · ${friendship.status.name}'),
          trailing: incoming
              ? Wrap(
                  children: [
                    IconButton(
                      onPressed: () => _respondFriend(friendship.id, true),
                      icon: const Icon(Icons.check),
                    ),
                    IconButton(
                      onPressed: () => _respondFriend(friendship.id, false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                )
              : null,
        );
      }),
    ],
  );

  Widget _inviteList() => ListView(
    children: _invites
        .map(
          (invite) => ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(invite.type.name),
            subtitle: Text(invite.campaignRoomId ?? ''),
            trailing: Wrap(
              children: [
                IconButton(
                  onPressed: () => _respondInvite(invite.id, true),
                  icon: const Icon(Icons.check),
                ),
                IconButton(
                  onPressed: () => _respondInvite(invite.id, false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        )
        .toList(),
  );

  Widget _notificationList() => ListView(
    children: _notifications
        .map(
          (value) => ListTile(
            leading: Icon(
              value.read ? Icons.notifications_none : Icons.notifications,
            ),
            title: Text(value.title),
            subtitle: Text(value.body),
            onTap: value.read
                ? null
                : () async {
                    await widget.service.post('/api/notifications/read', {
                      'id': value.id,
                    });
                    await _load();
                  },
          ),
        )
        .toList(),
  );

  Future<void> _createCampaign() async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建永久战役'),
        content: TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: '标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _title.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (title == null) return;
    await widget.service.post('/api/campaigns', {
      'campaignId': 'mist_harbor_test',
      'title': title,
      'privacy': CampaignRoomPrivacy.inviteOnly.name,
    });
    await _load();
  }

  Future<void> _requestFriend() async {
    await widget.service.post('/api/friends/request', {'handle': _handle.text});
    _handle.clear();
    await _load();
  }

  Future<void> _respondFriend(String id, bool accept) async {
    await widget.service.post('/api/friends/respond', {
      'friendshipId': id,
      'accept': accept,
    });
    await _load();
  }

  Future<void> _respondInvite(String id, bool accept) async {
    await widget.service.post('/api/invites/respond', {
      'inviteId': id,
      'accept': accept,
    });
    await _load();
  }

  void _showHub(PersistentCampaignRoom room) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Text(room.title, style: Theme.of(context).textTheme.headlineMedium),
            Text('当前章节：服务器 Revision ${room.revision}'),
            Text('最近游玩：${room.lastPlayedAt}'),
            if (room.announcement.isNotEmpty)
              Card(
                child: ListTile(
                  title: const Text('公告'),
                  subtitle: Text(room.announcement),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: room.lifecycle == CampaignRoomLifecycle.archived
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await widget.onContinue(room);
                    },
              icon: const Icon(Icons.play_arrow),
              label: Text(room.sessionId == null ? '开始战役' : '继续上次战役'),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _inviteMember(room),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('邀请成员'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _publishAnnouncement(room),
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('发布公告'),
                ),
              ],
            ),
            Text(
              '成员 ${room.members.length}/${room.maxMembers}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            ...room.members.map(
              (member) => ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(member.roomNickname ?? member.userId),
                subtitle: Text(
                  '${member.role.name} · ${member.status.name}\n角色：${member.characterId ?? '未绑定'}',
                ),
              ),
            ),
            Text('房间历史', style: Theme.of(context).textTheme.titleLarge),
            ...room.history.reversed
                .take(20)
                .map(
                  (event) => ListTile(
                    title: Text(event.message),
                    subtitle: Text(event.createdAt.toString()),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _inviteMember(PersistentCampaignRoom room) async {
    final controller = TextEditingController();
    final handle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('邀请战役成员'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '用户 ID',
            prefixText: '@',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (handle == null || handle.isEmpty) return;
    await widget.service.post('/api/campaigns/${room.id}/invite', {
      'handle': handle,
    });
    await _load();
  }

  Future<void> _publishAnnouncement(PersistentCampaignRoom room) async {
    final controller = TextEditingController(text: room.announcement);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('战役公告'),
        content: TextField(controller: controller, maxLines: 4),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('发布'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null) return;
    await widget.service.post('/api/campaigns/${room.id}/announcement', {
      'text': text,
    });
    await _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _handle.dispose();
    _title.dispose();
    super.dispose();
  }
}
