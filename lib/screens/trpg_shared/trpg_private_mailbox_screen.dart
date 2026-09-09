import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/skins/theme_background.dart';
import '../../models/trpg_models.dart';

class TrpgPrivateContact {
  const TrpgPrivateContact({
    required this.id,
    required this.name,
    this.subtitle = '',
    this.aliasIds = const [],
    this.isGm = false,
  });

  final String id;
  final String name;
  final String subtitle;
  final List<String> aliasIds;
  final bool isGm;

  bool matchesId(String value) => id == value || aliasIds.contains(value);
}

typedef TrpgPrivateSend =
    Future<List<TRPGPrivateMessage>?> Function(
      TrpgPrivateContact contact,
      String content,
    );

class TrpgPrivateMailboxScreen extends StatefulWidget {
  const TrpgPrivateMailboxScreen({
    required this.currentPlayerId,
    required this.contacts,
    required this.messages,
    required this.resolveName,
    required this.onSend,
    this.initialUnreadContactIds = const {},
    this.messageListenable,
    this.onContactOpened,
    super.key,
  });

  final String currentPlayerId;
  final List<TrpgPrivateContact> contacts;
  final List<TRPGPrivateMessage> messages;
  final String Function(String senderId) resolveName;
  final TrpgPrivateSend onSend;
  final Set<String> initialUnreadContactIds;
  final ValueListenable<List<TRPGPrivateMessage>>? messageListenable;
  final ValueChanged<String>? onContactOpened;

  @override
  State<TrpgPrivateMailboxScreen> createState() =>
      _TrpgPrivateMailboxScreenState();
}

class _TrpgPrivateMailboxScreenState extends State<TrpgPrivateMailboxScreen> {
  late List<TRPGPrivateMessage> _messages = [...widget.messages];
  late final Set<String> _unread = {...widget.initialUnreadContactIds};
  final Set<String> _readContacts = {};
  TrpgPrivateContact? _activeContact;
  final _composer = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    widget.messageListenable?.addListener(_syncExternalMessages);
  }

  @override
  void didUpdateWidget(covariant TrpgPrivateMailboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageListenable == widget.messageListenable) return;
    oldWidget.messageListenable?.removeListener(_syncExternalMessages);
    widget.messageListenable?.addListener(_syncExternalMessages);
  }

  @override
  void dispose() {
    widget.messageListenable?.removeListener(_syncExternalMessages);
    _composer.dispose();
    super.dispose();
  }

  void _syncExternalMessages() {
    final external = widget.messageListenable?.value;
    if (external == null || !mounted) return;
    final oldIds = _messages.map((message) => message.id).toSet();
    final incoming = external.where(
      (message) =>
          !oldIds.contains(message.id) &&
          message.senderId != widget.currentPlayerId,
    );
    final pending = _messages.where((message) {
      if (!message.id.startsWith('local-')) return false;
      return !external.any(
        (serverMessage) =>
            serverMessage.senderId == message.senderId &&
            serverMessage.content == message.content &&
            serverMessage.toGm == message.toGm &&
            serverMessage.createdAt.difference(message.createdAt).abs() <
                const Duration(seconds: 15),
      );
    });
    setState(() {
      _messages = [...external, ...pending];
      for (final message in incoming) {
        final contact = _orderedContacts
            .where((candidate) => _belongsTo(message, candidate))
            .firstOrNull;
        if (contact == null || contact.id == _activeContact?.id) continue;
        _unread.add(contact.id);
      }
    });
  }

  bool _involvesCurrent(TRPGPrivateMessage message) =>
      message.senderId == widget.currentPlayerId ||
      message.recipientIds.contains(widget.currentPlayerId);

  bool _belongsTo(TRPGPrivateMessage message, TrpgPrivateContact contact) {
    if (!_involvesCurrent(message)) return false;
    if (contact.isGm &&
        (message.toGm ||
            message.senderId == 'gm' ||
            message.senderId == 'system')) {
      return true;
    }
    return contact.matchesId(message.senderId) ||
        message.recipientIds.any(contact.matchesId);
  }

  List<TRPGPrivateMessage> _thread(TrpgPrivateContact contact) {
    final result = _messages
        .where((message) => _belongsTo(message, contact))
        .toList();
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  List<TrpgPrivateContact> get _orderedContacts {
    final contacts = <TrpgPrivateContact>[];
    final seen = <String>{};
    for (final contact in widget.contacts) {
      if (seen.add(contact.id)) contacts.add(contact);
    }

    // Old saves and dynamically generated NPC messages may contain a sender
    // that was not part of the screen's initial contact list.
    for (final message in _messages.where(_involvesCurrent)) {
      final peerIds = <String>{
        if (message.senderId != widget.currentPlayerId &&
            message.senderId != 'system')
          message.senderId,
        ...message.recipientIds.where(
          (id) => id != widget.currentPlayerId && id != 'system',
        ),
      };
      for (final peerId in peerIds) {
        final normalized = peerId == 'gm' ? 'gm' : peerId;
        if (!seen.add(normalized)) continue;
        contacts.add(
          TrpgPrivateContact(
            id: normalized,
            name: peerId == 'gm' ? 'GM 主持' : widget.resolveName(peerId),
            subtitle: peerId == 'gm' ? '主持人与规则裁定' : '私人会话',
            isGm: peerId == 'gm',
          ),
        );
      }
    }

    contacts.sort((a, b) {
      final aThread = _thread(a);
      final bThread = _thread(b);
      final aTime = aThread.isEmpty ? null : aThread.last.createdAt;
      final bTime = bThread.isEmpty ? null : bThread.last.createdAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return contacts;
  }

  void _open(TrpgPrivateContact contact) {
    setState(() {
      _activeContact = contact;
      _unread.remove(contact.id);
      _readContacts.add(contact.id);
    });
    widget.onContactOpened?.call(contact.id);
  }

  Future<void> _send() async {
    final contact = _activeContact;
    final content = _composer.text.trim();
    if (contact == null || content.isEmpty || _sending) return;
    final now = DateTime.now();
    final optimistic = TRPGPrivateMessage(
      id: 'local-${now.microsecondsSinceEpoch}',
      senderId: widget.currentPlayerId,
      recipientIds: [widget.currentPlayerId, contact.id],
      content: content,
      createdAt: now,
      toGm: contact.isGm,
    );
    setState(() {
      _sending = true;
      _messages = [..._messages, optimistic];
      _composer.clear();
    });
    try {
      final refreshed = await widget.onSend(contact, content);
      if (!mounted) return;
      if (refreshed != null) {
        final confirmed = refreshed.any(
          (message) =>
              message.senderId == widget.currentPlayerId &&
              message.content == content &&
              message.toGm == contact.isGm &&
              message.createdAt.difference(now).abs() <
                  const Duration(seconds: 15),
        );
        setState(() => _messages = [...refreshed, if (!confirmed) optimistic]);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((message) => message.id == optimistic.id);
        _composer.text = content;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('私信发送失败：$error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeContact;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: active == null
            ? null
            : IconButton(
                tooltip: '返回会话列表',
                onPressed: () => setState(() => _activeContact = null),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(active?.name ?? '私密消息'),
        actions: active == null
            ? const [
                Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Icon(Icons.lock_outline_rounded),
                ),
              ]
            : null,
      ),
      body: ThemeBackground(
        chat: true,
        child: active == null ? _buildMailbox() : _buildConversation(active),
      ),
    );
  }

  Widget _buildMailbox() {
    final contacts = _orderedContacts;
    if (contacts.isEmpty) {
      return const Center(child: Text('暂无可私聊的联系人'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: contacts.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
      itemBuilder: (context, index) {
        final contact = contacts[index];
        final thread = _thread(contact);
        final latest = thread.lastOrNull;
        final unread =
            _unread.contains(contact.id) && !_readContacts.contains(contact.id);
        return Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .82),
          child: ListTile(
            minVerticalPadding: 12,
            leading: _avatar(contact, unread: unread),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    contact.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (latest != null)
                  Text(
                    _time(latest.createdAt),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
            subtitle: Text(
              latest?.content ?? contact.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _open(contact),
          ),
        );
      },
    );
  }

  Widget _avatar(TrpgPrivateContact contact, {required bool unread}) => Stack(
    clipBehavior: Clip.none,
    children: [
      CircleAvatar(
        radius: 25,
        child: contact.isGm
            ? const Icon(Icons.smart_toy_outlined)
            : Text(
                contact.name.trim().isEmpty ? '?' : contact.name.trim()[0],
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
      ),
      if (unread)
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
    ],
  );

  Widget _buildConversation(TrpgPrivateContact contact) {
    final thread = _thread(contact);
    return Column(
      children: [
        Expanded(
          child: thread.isEmpty
              ? Center(child: Text('还没有与 ${contact.name} 的消息'))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
                  itemCount: thread.length,
                  itemBuilder: (context, index) {
                    final message = thread[thread.length - 1 - index];
                    return _messageBubble(message, contact);
                  },
                ),
        ),
        _composerBar(contact),
      ],
    );
  }

  Widget _messageBubble(
    TRPGPrivateMessage message,
    TrpgPrivateContact contact,
  ) {
    final mine = message.senderId == widget.currentPlayerId;
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .78,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: mine
              ? colors.primaryContainer.withValues(alpha: .94)
              : colors.surfaceContainerHigh.withValues(alpha: .94),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message.senderId == 'system' ? '私密系统' : contact.name,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            SelectableText(message.content),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _time(message.createdAt),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composerBar(TrpgPrivateContact contact) => SafeArea(
    top: false,
    child: Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '发送给 ${contact.name}…',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: '发送私信',
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    ),
  );

  String _time(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final clock =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return clock;
    }
    return '${local.month}/${local.day} $clock';
  }
}
