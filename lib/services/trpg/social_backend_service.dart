import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../models/social_models.dart';
import 'room_permission_service.dart';

class AuthenticatedIdentity {
  const AuthenticatedIdentity({
    required this.account,
    required this.deviceSession,
  });
  final UserAccount account;
  final DeviceSession deviceSession;
}

class SocialBackendService {
  SocialBackendService({required this.directory});

  final String directory;
  static const _uuid = Uuid();
  static final _random = Random.secure();
  final _accounts = <String, UserAccount>{};
  final _passwordHashes = <String, String>{};
  final _devices = <String, DeviceSession>{};
  final _friendships = <String, Friendship>{};
  final _invites = <String, SocialInvite>{};
  final _campaigns = <String, PersistentCampaignRoom>{};
  final _notifications = <String, CampaignNotification>{};
  final _recentPlayers = <String, Set<String>>{};
  Future<void> _writeQueue = Future.value();

  Iterable<UserAccount> get accounts => _accounts.values;
  Iterable<PersistentCampaignRoom> get campaigns => _campaigns.values;

  Future<void> initialize() async {
    final file = _stateFile;
    if (!await file.exists()) return;
    final raw = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    for (final value in (raw['accounts'] as List? ?? const [])) {
      final map = (value as Map).cast<String, Object?>();
      final account = UserAccount.fromJson(map);
      _accounts[account.userId] = account;
      _passwordHashes[account.userId] = map['passwordHash'] as String? ?? '';
    }
    for (final value in (raw['devices'] as List? ?? const [])) {
      final device = DeviceSession.fromJson(
        (value as Map).cast<String, Object?>(),
      );
      _devices[device.id] = device;
    }
    for (final value in (raw['friendships'] as List? ?? const [])) {
      final friendship = Friendship.fromJson(
        (value as Map).cast<String, Object?>(),
      );
      _friendships[friendship.id] = friendship;
    }
    for (final value in (raw['invites'] as List? ?? const [])) {
      final invite = SocialInvite.fromJson(
        (value as Map).cast<String, Object?>(),
      );
      _invites[invite.id] = invite;
    }
    for (final value in (raw['campaigns'] as List? ?? const [])) {
      final campaign = PersistentCampaignRoom.fromJson(
        (value as Map).cast<String, Object?>(),
      );
      _campaigns[campaign.id] = campaign;
    }
    for (final value in (raw['notifications'] as List? ?? const [])) {
      final notification = CampaignNotification.fromJson(
        (value as Map).cast<String, Object?>(),
      );
      _notifications[notification.id] = notification;
    }
    final recent = raw['recentPlayers'] as Map? ?? const {};
    for (final entry in recent.entries) {
      _recentPlayers[entry.key.toString()] = (entry.value as List? ?? const [])
          .map((value) => value.toString())
          .toSet();
    }
  }

  Future<AuthTokens> register({
    required String handle,
    required String displayName,
    required String password,
    required String deviceName,
    required String platform,
  }) async {
    final normalized = _normalizeHandle(handle);
    _validatePassword(password);
    if (_accounts.values.any((value) => value.handle == normalized)) {
      throw StateError('用户 ID 已存在');
    }
    final now = DateTime.now();
    final account = UserAccount(
      userId: _uuid.v4(),
      handle: normalized,
      displayName: displayName.trim().isEmpty ? normalized : displayName.trim(),
      createdAt: now,
      lastOnlineAt: now,
      presence: PresenceStatus.online,
    );
    _accounts[account.userId] = account;
    _passwordHashes[account.userId] = BCrypt.hashpw(
      password,
      BCrypt.gensalt(logRounds: 12),
    );
    final tokens = _createTokens(account, deviceName, platform);
    await _persist();
    return tokens;
  }

  Future<AuthTokens> login({
    required String handle,
    required String password,
    required String deviceName,
    required String platform,
  }) async {
    final normalized = _normalizeHandle(handle);
    final account = _accounts.values
        .where((value) => value.handle == normalized)
        .firstOrNull;
    final hash = account == null ? null : _passwordHashes[account.userId];
    if (account == null || hash == null || !BCrypt.checkpw(password, hash)) {
      throw StateError('用户 ID 或密码错误');
    }
    if (account.status != AccountStatus.active) {
      throw StateError('账号不可用');
    }
    final updated = account.copyWith(
      lastOnlineAt: DateTime.now(),
      presence: PresenceStatus.online,
    );
    _accounts[updated.userId] = updated;
    final tokens = _createTokens(updated, deviceName, platform);
    await _persist();
    return tokens;
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final hash = _hashToken(refreshToken);
    final device = _devices.values
        .where(
          (value) =>
              value.refreshTokenHash == hash &&
              !value.revoked &&
              value.refreshExpiresAt.isAfter(DateTime.now()),
        )
        .firstOrNull;
    if (device == null) throw StateError('Refresh Token 已失效');
    final account = _accounts[device.userId]!;
    _devices.remove(device.id);
    final tokens = _createTokens(account, device.deviceName, device.platform);
    await _persist();
    return tokens;
  }

  AuthenticatedIdentity authenticate(String accessToken) {
    final hash = _hashToken(accessToken);
    final device = _devices.values
        .where(
          (value) =>
              value.tokenHash == hash &&
              !value.revoked &&
              value.expiresAt.isAfter(DateTime.now()),
        )
        .firstOrNull;
    if (device == null) throw StateError('Access Token 无效或已过期');
    final account = _accounts[device.userId];
    if (account == null || account.status != AccountStatus.active) {
      throw StateError('账号不可用');
    }
    return AuthenticatedIdentity(account: account, deviceSession: device);
  }

  Future<void> logout(String accessToken, {bool allDevices = false}) async {
    final identity = authenticate(accessToken);
    if (allDevices) {
      _devices.removeWhere(
        (_, value) => value.userId == identity.account.userId,
      );
    } else {
      _devices.remove(identity.deviceSession.id);
    }
    if (!_devices.values.any(
      (value) => value.userId == identity.account.userId && !value.revoked,
    )) {
      _accounts[identity.account.userId] = identity.account.copyWith(
        presence: PresenceStatus.offline,
        lastOnlineAt: DateTime.now(),
      );
    }
    await _persist();
  }

  Future<void> deleteAccount(String userId) async {
    if (_campaigns.values.any(
      (value) =>
          value.ownerUserId == userId &&
          value.lifecycle != CampaignRoomLifecycle.archived &&
          value.lifecycle != CampaignRoomLifecycle.deleted,
    )) {
      throw StateError('请先转移、归档或删除你拥有的战役');
    }
    final account = _accounts[userId];
    if (account == null) throw StateError('账号不存在');
    _accounts[userId] = account.copyWith(
      status: AccountStatus.deleted,
      presence: PresenceStatus.offline,
      displayName: '已删除用户',
    );
    _passwordHashes.remove(userId);
    _devices.removeWhere((_, value) => value.userId == userId);
    await _persist();
  }

  List<DeviceSession> devices(String userId) => _devices.values
      .where((value) => value.userId == userId && !value.revoked)
      .toList();

  Future<void> updateDeviceCapability(
    String deviceId, {
    required bool supportsAIHost,
    required List<String> providerTypes,
    required bool toolCallingVerified,
  }) async {
    final current = _devices[deviceId];
    if (current == null) throw StateError('设备会话不存在');
    _devices[deviceId] = DeviceSession(
      id: current.id,
      userId: current.userId,
      deviceName: current.deviceName,
      platform: current.platform,
      tokenHash: current.tokenHash,
      refreshTokenHash: current.refreshTokenHash,
      createdAt: current.createdAt,
      expiresAt: current.expiresAt,
      refreshExpiresAt: current.refreshExpiresAt,
      lastSeenAt: DateTime.now(),
      revoked: current.revoked,
      supportsAIHost: supportsAIHost,
      providerTypes: providerTypes,
      toolCallingVerified: toolCallingVerified,
    );
    await _persist();
  }

  List<UserAccount> searchUsers(String requesterId, String handle) {
    final query = handle.trim().toLowerCase().replaceFirst('@', '');
    return _accounts.values
        .where(
          (value) =>
              value.userId != requesterId &&
              value.status == AccountStatus.active &&
              value.handle.contains(query) &&
              !_isBlocked(requesterId, value.userId),
        )
        .take(20)
        .map(_publicAccount)
        .toList();
  }

  Future<Friendship> requestFriend(String requesterId, String handle) async {
    final target = _accounts.values
        .where((value) => value.handle == _normalizeHandle(handle))
        .firstOrNull;
    if (target == null || target.userId == requesterId) {
      throw StateError('找不到该用户');
    }
    if (_isBlocked(requesterId, target.userId)) {
      throw StateError('无法向该用户发送请求');
    }
    final existing = _relationship(requesterId, target.userId);
    if (existing?.status == FriendshipStatus.accepted ||
        existing?.status == FriendshipStatus.pending) {
      throw StateError('好友关系或请求已存在');
    }
    final now = DateTime.now();
    final friendship = Friendship(
      id: _uuid.v4(),
      requesterUserId: requesterId,
      addresseeUserId: target.userId,
      createdAt: now,
      updatedAt: now,
    );
    _friendships[friendship.id] = friendship;
    _notify(
      target.userId,
      NotificationType.friendRequest,
      '新的好友请求',
      '${_accounts[requesterId]!.displayName} 请求添加你为好友',
      metadata: {'friendshipId': friendship.id},
    );
    await _persist();
    return friendship;
  }

  Future<Friendship> respondFriend(
    String userId,
    String friendshipId, {
    required bool accept,
  }) async {
    final current = _friendships[friendshipId];
    if (current == null || current.addresseeUserId != userId) {
      throw StateError('好友请求不存在');
    }
    final updated = current.copyWith(
      status: accept ? FriendshipStatus.accepted : FriendshipStatus.removed,
      updatedAt: DateTime.now(),
    );
    _friendships[friendshipId] = updated;
    if (accept) {
      _notify(
        current.requesterUserId,
        NotificationType.friendAccepted,
        '好友请求已接受',
        '${_accounts[userId]!.displayName} 已成为你的好友',
      );
    }
    await _persist();
    return updated;
  }

  Future<void> block(String userId, String targetUserId) async {
    if (!_accounts.containsKey(targetUserId) || userId == targetUserId) {
      throw StateError('用户不存在');
    }
    final existing = _relationship(userId, targetUserId);
    final now = DateTime.now();
    final blocked = Friendship(
      id: existing?.id ?? _uuid.v4(),
      requesterUserId: userId,
      addresseeUserId: targetUserId,
      status: FriendshipStatus.blocked,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    _friendships.removeWhere(
      (_, value) => value.involves(userId) && value.involves(targetUserId),
    );
    _friendships[blocked.id] = blocked;
    await _persist();
  }

  List<Map<String, Object?>> friends(String userId) => _friendships.values
      .where(
        (value) =>
            value.involves(userId) &&
            const {
              FriendshipStatus.pending,
              FriendshipStatus.accepted,
              FriendshipStatus.blocked,
            }.contains(value.status),
      )
      .map(
        (value) => {
          'friendship': value.toJson(),
          'account': _publicAccount(_accounts[value.other(userId)]!).toJson(),
        },
      )
      .toList();

  Future<PersistentCampaignRoom> createCampaign({
    required String ownerUserId,
    required String campaignId,
    required String title,
    String description = '',
    int maxMembers = 6,
    CampaignRoomPrivacy privacy = CampaignRoomPrivacy.inviteOnly,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final roomPlayerId = _uuid.v4();
    final room = PersistentCampaignRoom(
      id: id,
      campaignId: campaignId,
      ownerUserId: ownerUserId,
      title: title.trim().isEmpty ? '未命名战役' : title.trim(),
      description: description.trim(),
      inviteCode: _shortCode(),
      privacy: privacy,
      maxMembers: maxMembers.clamp(1, 12),
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
      members: [
        CampaignMember(
          userId: ownerUserId,
          roomPlayerId: roomPlayerId,
          role: CampaignMemberRole.owner,
          joinedAt: now,
          lastPlayedAt: now,
        ),
      ],
      history: [
        CampaignHistoryEntry(
          id: _uuid.v4(),
          type: 'campaign_created',
          message: '${_accounts[ownerUserId]!.displayName} 创建了战役',
          actorUserId: ownerUserId,
          createdAt: now,
        ),
      ],
    );
    _campaigns[id] = room;
    await _persist();
    return room;
  }

  List<PersistentCampaignRoom> campaignsFor(String userId) =>
      _campaigns.values
          .where(
            (value) =>
                value.deletedAt == null &&
                value.members.any(
                  (member) =>
                      member.userId == userId &&
                      member.status != MembershipStatus.banned,
                ),
          )
          .toList()
        ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));

  PersistentCampaignRoom campaignFor(String userId, String id) {
    final room = _campaigns[id];
    if (room == null || !room.hasMember(userId)) {
      throw StateError('战役不存在或无权访问');
    }
    return room;
  }

  Future<SocialInvite> inviteCampaign(
    String actorUserId,
    String campaignId,
    String targetHandle,
  ) async {
    final room = campaignFor(actorUserId, campaignId);
    const RoomPermissionService().require(
      room,
      actorUserId,
      RoomPermission.invite,
    );
    final target = _accounts.values
        .where((value) => value.handle == _normalizeHandle(targetHandle))
        .firstOrNull;
    if (target == null || _isBlocked(actorUserId, target.userId)) {
      throw StateError('无法邀请该用户');
    }
    if (room.bannedUserIds.contains(target.userId)) {
      throw StateError('该用户已被房间封禁');
    }
    if (room.hasMember(target.userId)) throw StateError('该用户已经是成员');
    if (room.members.length >= room.maxMembers) throw StateError('战役成员已满');
    final existing = _invites.values.any(
      (value) =>
          value.campaignRoomId == campaignId &&
          value.recipientUserId == target.userId &&
          value.status == InviteStatus.pending,
    );
    if (existing) throw StateError('邀请已经发送');
    final now = DateTime.now();
    final invite = SocialInvite(
      id: _uuid.v4(),
      type: SocialInviteType.campaignInvite,
      senderUserId: actorUserId,
      recipientUserId: target.userId,
      campaignRoomId: campaignId,
      code: room.inviteCode,
      createdAt: now,
      expiresAt: now.add(const Duration(days: 7)),
    );
    _invites[invite.id] = invite;
    _notify(
      target.userId,
      NotificationType.campaignInvite,
      '战役邀请',
      '${_accounts[actorUserId]!.displayName} 邀请你加入《${room.title}》',
      campaignRoomId: room.id,
      metadata: {'inviteId': invite.id},
    );
    await _persist();
    return invite;
  }

  Future<PersistentCampaignRoom> respondCampaignInvite(
    String userId,
    String inviteId, {
    required bool accept,
  }) async {
    final invite = _invites[inviteId];
    if (invite == null ||
        invite.recipientUserId != userId ||
        invite.status != InviteStatus.pending ||
        invite.expiresAt.isBefore(DateTime.now())) {
      throw StateError('邀请无效或已过期');
    }
    _invites[inviteId] = invite.copyWith(
      status: accept ? InviteStatus.accepted : InviteStatus.declined,
    );
    final room = _campaigns[invite.campaignRoomId]!;
    if (!accept) {
      await _persist();
      return room;
    }
    if (room.bannedUserIds.contains(userId)) {
      throw StateError('已被该房间禁止加入');
    }
    if (room.members.length >= room.maxMembers) throw StateError('战役成员已满');
    final now = DateTime.now();
    final existing = room.member(userId);
    final member =
        existing?.copyWith(status: MembershipStatus.active) ??
        CampaignMember(
          userId: userId,
          roomPlayerId: _uuid.v4(),
          role: CampaignMemberRole.player,
          joinedAt: now,
          lastPlayedAt: now,
        );
    final updated = room.copyWith(
      members: [
        ...room.members.where((value) => value.userId != userId),
        member,
      ],
      history: [
        ...room.history,
        CampaignHistoryEntry(
          id: _uuid.v4(),
          type: 'member_joined',
          message: '${_accounts[userId]!.displayName} 加入了战役',
          actorUserId: userId,
          createdAt: now,
        ),
      ],
      updatedAt: now,
      revision: room.revision + 1,
    );
    _campaigns[room.id] = updated;
    _recentPlayers
        .putIfAbsent(userId, () => {})
        .addAll(
          updated.members
              .map((value) => value.userId)
              .where((id) => id != userId),
        );
    await _persist();
    return updated;
  }

  Future<PersistentCampaignRoom> bindCharacter(
    String userId,
    String campaignId,
    String characterId, {
    required int expectedRevision,
  }) async {
    final room = campaignFor(userId, campaignId);
    if (room.revision != expectedRevision) {
      throw StateError('revision_conflict');
    }
    final member = room.member(userId)!;
    if (member.characterId != null &&
        member.characterId != characterId &&
        !room.allowCharacterChange &&
        room.lifecycle != CampaignRoomLifecycle.idle) {
      throw StateError('战役进行后不允许直接更换角色');
    }
    final now = DateTime.now();
    final updated = room.copyWith(
      members: room.members
          .map(
            (value) => value.userId == userId
                ? value.copyWith(characterId: characterId, lastPlayedAt: now)
                : value,
          )
          .toList(),
      updatedAt: now,
      revision: room.revision + 1,
    );
    _campaigns[room.id] = updated;
    await _persist();
    return updated;
  }

  Future<PersistentCampaignRoom> announce(
    String actorUserId,
    String campaignId,
    String text,
  ) async {
    final room = campaignFor(actorUserId, campaignId);
    const RoomPermissionService().require(
      room,
      actorUserId,
      RoomPermission.announce,
    );
    final now = DateTime.now();
    final updated = room.copyWith(
      announcement: text.trim(),
      updatedAt: now,
      revision: room.revision + 1,
      history: [
        ...room.history,
        CampaignHistoryEntry(
          id: _uuid.v4(),
          type: 'announcement',
          message: '发布公告：${text.trim()}',
          actorUserId: actorUserId,
          createdAt: now,
        ),
      ],
    );
    _campaigns[room.id] = updated;
    for (final member in room.members.where(
      (value) => value.userId != actorUserId,
    )) {
      _notify(
        member.userId,
        NotificationType.announcement,
        room.title,
        text.trim(),
        campaignRoomId: room.id,
      );
    }
    await _persist();
    return updated;
  }

  Future<PersistentCampaignRoom> updateHostPolicy(
    String actorUserId,
    String campaignId,
    AIHostPolicy policy,
  ) async {
    final room = campaignFor(actorUserId, campaignId);
    const RoomPermissionService().require(
      room,
      actorUserId,
      RoomPermission.changeHost,
    );
    final validUsers = room.members.map((value) => value.userId).toSet();
    if (policy.preferredProviderUserId != null &&
        !validUsers.contains(policy.preferredProviderUserId)) {
      throw StateError('首选 Host 必须是战役成员');
    }
    if (policy.backupProviderUserIds.any(
      (value) => !validUsers.contains(value),
    )) {
      throw StateError('备用 Host 必须是战役成员');
    }
    final now = DateTime.now();
    final updated = room.copyWith(
      aiHostPolicy: policy,
      updatedAt: now,
      revision: room.revision + 1,
      history: [
        ...room.history,
        CampaignHistoryEntry(
          id: _uuid.v4(),
          type: 'host_policy_changed',
          message: 'AI Host 优先级已更新',
          actorUserId: actorUserId,
          createdAt: now,
        ),
      ],
    );
    _campaigns[room.id] = updated;
    await _persist();
    return updated;
  }

  Future<PersistentCampaignRoom> setMemberRole(
    String actorUserId,
    String campaignId,
    String targetUserId,
    CampaignMemberRole role,
  ) async {
    final room = campaignFor(actorUserId, campaignId);
    const RoomPermissionService().require(
      room,
      actorUserId,
      RoomPermission.manageRoles,
    );
    if (role == CampaignMemberRole.owner) {
      throw StateError('房主转移需要单独确认流程');
    }
    final target = room.member(targetUserId);
    if (target == null || target.role == CampaignMemberRole.owner) {
      throw StateError('不能修改该成员角色');
    }
    final updated = room.copyWith(
      members: room.members
          .map(
            (value) => value.userId == targetUserId
                ? value.copyWith(role: role)
                : value,
          )
          .toList(),
      updatedAt: DateTime.now(),
      revision: room.revision + 1,
    );
    _campaigns[room.id] = updated;
    await _persist();
    return updated;
  }

  Future<SocialInvite> requestOwnershipTransfer(
    String ownerUserId,
    String campaignId,
    String targetUserId,
  ) async {
    final room = campaignFor(ownerUserId, campaignId);
    const RoomPermissionService().require(
      room,
      ownerUserId,
      RoomPermission.transferOwnership,
    );
    final target = room.member(targetUserId);
    if (target == null || target.status != MembershipStatus.active) {
      throw StateError('新 Owner 必须是有效战役成员');
    }
    final now = DateTime.now();
    final invite = SocialInvite(
      id: _uuid.v4(),
      type: SocialInviteType.ownershipTransfer,
      senderUserId: ownerUserId,
      recipientUserId: targetUserId,
      campaignRoomId: campaignId,
      createdAt: now,
      expiresAt: now.add(const Duration(days: 3)),
    );
    _invites[invite.id] = invite;
    _notify(
      targetUserId,
      NotificationType.campaignInvite,
      '房主转移确认',
      '${_accounts[ownerUserId]!.displayName} 希望将《${room.title}》转移给你',
      campaignRoomId: campaignId,
      metadata: {'inviteId': invite.id, 'ownershipTransfer': true},
    );
    await _persist();
    return invite;
  }

  Future<PersistentCampaignRoom> respondOwnershipTransfer(
    String userId,
    String inviteId, {
    required bool accept,
  }) async {
    final invite = _invites[inviteId];
    if (invite == null ||
        invite.type != SocialInviteType.ownershipTransfer ||
        invite.recipientUserId != userId ||
        invite.status != InviteStatus.pending ||
        invite.expiresAt.isBefore(DateTime.now())) {
      throw StateError('房主转移请求无效或已过期');
    }
    _invites[inviteId] = invite.copyWith(
      status: accept ? InviteStatus.accepted : InviteStatus.declined,
    );
    final room = _campaigns[invite.campaignRoomId]!;
    if (!accept) {
      await _persist();
      return room;
    }
    final now = DateTime.now();
    final updated = room.copyWith(
      ownerUserId: userId,
      members: room.members
          .map(
            (value) => value.userId == userId
                ? value.copyWith(role: CampaignMemberRole.owner)
                : value.userId == room.ownerUserId
                ? value.copyWith(role: CampaignMemberRole.admin)
                : value,
          )
          .toList(),
      updatedAt: now,
      revision: room.revision + 1,
      history: [
        ...room.history,
        CampaignHistoryEntry(
          id: _uuid.v4(),
          type: 'ownership_transferred',
          message: '战役 Owner 已转移给 ${_accounts[userId]!.displayName}',
          actorUserId: userId,
          createdAt: now,
        ),
      ],
    );
    _campaigns[room.id] = updated;
    await _persist();
    return updated;
  }

  Future<PersistentCampaignRoom> manageMember(
    String actorUserId,
    String campaignId,
    String targetUserId, {
    required bool ban,
  }) async {
    final room = campaignFor(actorUserId, campaignId);
    const RoomPermissionService().require(
      room,
      actorUserId,
      RoomPermission.kick,
    );
    final target = room.member(targetUserId);
    if (target == null || target.role == CampaignMemberRole.owner) {
      throw StateError('不能移除该成员');
    }
    final now = DateTime.now();
    final updated = room.copyWith(
      members: room.members
          .map(
            (value) => value.userId == targetUserId
                ? value.copyWith(
                    status: ban
                        ? MembershipStatus.banned
                        : MembershipStatus.inactive,
                  )
                : value,
          )
          .toList(),
      bannedUserIds: ban
          ? {...room.bannedUserIds, targetUserId}.toList()
          : room.bannedUserIds,
      updatedAt: now,
      revision: room.revision + 1,
      history: [
        ...room.history,
        CampaignHistoryEntry(
          id: _uuid.v4(),
          type: ban ? 'member_banned' : 'member_removed',
          message: ban ? '成员已被封禁' : '成员已移出并保留角色历史',
          actorUserId: actorUserId,
          createdAt: now,
          metadata: {'targetUserId': targetUserId},
        ),
      ],
    );
    _campaigns[room.id] = updated;
    await _persist();
    return updated;
  }

  Future<PersistentCampaignRoom> softDeleteCampaign(
    String ownerUserId,
    String campaignId,
  ) async {
    final room = campaignFor(ownerUserId, campaignId);
    const RoomPermissionService().require(
      room,
      ownerUserId,
      RoomPermission.delete,
    );
    final updated = room.copyWith(
      lifecycle: CampaignRoomLifecycle.deleted,
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      revision: room.revision + 1,
    );
    _campaigns[room.id] = updated;
    await _persist();
    return updated;
  }

  PersistentCampaignRoom? inspectCampaign(String campaignId) =>
      _campaigns[campaignId];

  Future<PersistentCampaignRoom> recordHistory(
    String campaignId, {
    required String type,
    required String message,
    required String actorUserId,
    Map<String, Object?> metadata = const {},
  }) async {
    final room = _campaigns[campaignId];
    if (room == null) throw StateError('永久战役不存在');
    final updated = room.copyWith(
      updatedAt: DateTime.now(),
      revision: room.revision + 1,
      history: [
        ...room.history,
        CampaignHistoryEntry(
          id: _uuid.v4(),
          type: type,
          message: message,
          actorUserId: actorUserId,
          createdAt: DateTime.now(),
          metadata: metadata,
        ),
      ],
    );
    _campaigns[campaignId] = updated;
    await _persist();
    return updated;
  }

  Future<PersistentCampaignRoom> archive(
    String actorUserId,
    String campaignId, {
    String finalSummary = '',
  }) async {
    final room = campaignFor(actorUserId, campaignId);
    const RoomPermissionService().require(
      room,
      actorUserId,
      RoomPermission.archive,
    );
    final now = DateTime.now();
    final updated = room.copyWith(
      lifecycle: CampaignRoomLifecycle.archived,
      finalSummary: finalSummary,
      updatedAt: now,
      revision: room.revision + 1,
      history: [
        ...room.history,
        CampaignHistoryEntry(
          id: _uuid.v4(),
          type: 'campaign_archived',
          message: '战役已归档',
          actorUserId: actorUserId,
          createdAt: now,
        ),
      ],
    );
    _campaigns[room.id] = updated;
    await _persist();
    return updated;
  }

  Future<PersistentCampaignRoom> startPlaySession(
    String campaignId, {
    required String sessionId,
    required List<String> participantUserIds,
    required int startingRevision,
  }) async {
    final room = _campaigns[campaignId];
    if (room == null) throw StateError('永久战役不存在');
    final now = DateTime.now();
    final play = PlaySessionRecord(
      id: _uuid.v4(),
      campaignRoomId: campaignId,
      startedAt: now,
      participants: participantUserIds,
      startingRevision: startingRevision,
    );
    final updated = room.copyWith(
      sessionId: sessionId,
      lifecycle: CampaignRoomLifecycle.active,
      playSessions: [...room.playSessions, play],
      lastPlayedAt: now,
      updatedAt: now,
      revision: room.revision + 1,
      history: [
        ...room.history,
        CampaignHistoryEntry(
          id: _uuid.v4(),
          type: 'play_session_started',
          message: '开始了新的跑团 Session',
          createdAt: now,
        ),
      ],
    );
    _campaigns[campaignId] = updated;
    for (final member in room.members) {
      if (!participantUserIds.contains(member.userId)) {
        _notify(
          member.userId,
          NotificationType.campaignStarted,
          room.title,
          '战役已经开始，本次未在线的角色保持 inactive。',
          campaignRoomId: room.id,
        );
      }
    }
    await _persist();
    return updated;
  }

  Future<PersistentCampaignRoom> endPlaySession(
    String campaignId, {
    required int endingRevision,
  }) async {
    final room = _campaigns[campaignId];
    if (room == null) throw StateError('永久战役不存在');
    final now = DateTime.now();
    final sessions = [...room.playSessions];
    final activeIndex = sessions.lastIndexWhere(
      (value) => value.endedAt == null,
    );
    if (activeIndex >= 0) {
      final active = sessions[activeIndex];
      sessions[activeIndex] = PlaySessionRecord(
        id: active.id,
        campaignRoomId: active.campaignRoomId,
        startedAt: active.startedAt,
        endedAt: now,
        participants: active.participants,
        startingRevision: active.startingRevision,
        endingRevision: endingRevision,
      );
    }
    final updated = room.copyWith(
      lifecycle: CampaignRoomLifecycle.paused,
      playSessions: sessions,
      lastPlayedAt: now,
      updatedAt: now,
      revision: room.revision + 1,
    );
    _campaigns[campaignId] = updated;
    await _persist();
    return updated;
  }

  List<SocialInvite> invitesFor(String userId) => _invites.values
      .where(
        (value) =>
            value.recipientUserId == userId &&
            value.status == InviteStatus.pending &&
            value.expiresAt.isAfter(DateTime.now()),
      )
      .toList();

  List<CampaignNotification> notifications(String userId) =>
      _notifications.values.where((value) => value.userId == userId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> readNotification(String userId, String id) async {
    final value = _notifications[id];
    if (value == null || value.userId != userId) throw StateError('通知不存在');
    _notifications[id] = value.copyWith(read: true);
    await _persist();
  }

  List<UserAccount> recentPlayers(String userId) =>
      (_recentPlayers[userId] ?? const <String>{})
          .map((id) => _accounts[id])
          .whereType<UserAccount>()
          .map(_publicAccount)
          .toList();

  Future<String> createBackup(
    String actorUserId,
    String campaignId,
    Map<String, Object?> sessionJson,
  ) async {
    final room = campaignFor(actorUserId, campaignId);
    const RoomPermissionService().require(
      room,
      actorUserId,
      RoomPermission.backup,
    );
    final backupDir = Directory(
      '$directory${Platform.pathSeparator}backups${Platform.pathSeparator}$campaignId',
    );
    await backupDir.create(recursive: true);
    final id = '${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';
    final file = File('${backupDir.path}${Platform.pathSeparator}$id.json');
    await file.writeAsString(
      jsonEncode({
        'createdAt': DateTime.now().toIso8601String(),
        'revision': room.revision,
        'room': room.toJson(),
        'session': sessionJson,
      }),
      flush: true,
    );
    final files = await backupDir
        .list()
        .where((value) => value is File && value.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    for (final old in files.skip(10)) {
      await old.delete();
    }
    return id;
  }

  Future<Map<String, Object?>> restoreBackup(
    String actorUserId,
    String campaignId,
    String backupId,
  ) async {
    final room = campaignFor(actorUserId, campaignId);
    const RoomPermissionService().require(
      room,
      actorUserId,
      RoomPermission.restore,
    );
    final file = File(
      '$directory${Platform.pathSeparator}backups${Platform.pathSeparator}'
      '$campaignId${Platform.pathSeparator}$backupId.json',
    );
    if (!await file.exists()) throw StateError('备份不存在');
    final raw = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    final restoredRoom = PersistentCampaignRoom.fromJson(
      (raw['room'] as Map).cast<String, Object?>(),
    );
    final now = DateTime.now();
    _campaigns[campaignId] = restoredRoom.copyWith(
      revision: room.revision + 1,
      updatedAt: now,
      history: [
        ...restoredRoom.history,
        CampaignHistoryEntry(
          id: _uuid.v4(),
          type: 'backup_restored',
          message: '战役已从备份恢复',
          actorUserId: actorUserId,
          createdAt: now,
          metadata: {'backupId': backupId},
        ),
      ],
    );
    await _persist();
    return (raw['session'] as Map).cast<String, Object?>();
  }

  AuthTokens _createTokens(
    UserAccount account,
    String deviceName,
    String platform,
  ) {
    final now = DateTime.now();
    final access = _token();
    final refresh = _token();
    final device = DeviceSession(
      id: _uuid.v4(),
      userId: account.userId,
      deviceName: deviceName.trim().isEmpty ? 'Unknown Device' : deviceName,
      platform: platform.trim().isEmpty ? 'unknown' : platform,
      tokenHash: _hashToken(access),
      refreshTokenHash: _hashToken(refresh),
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      refreshExpiresAt: now.add(const Duration(days: 30)),
      lastSeenAt: now,
    );
    _devices[device.id] = device;
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: device.expiresAt,
      account: account,
      deviceSessionId: device.id,
    );
  }

  void _notify(
    String userId,
    NotificationType type,
    String title,
    String body, {
    String? campaignRoomId,
    Map<String, Object?> metadata = const {},
  }) {
    final notification = CampaignNotification(
      id: _uuid.v4(),
      userId: userId,
      type: type,
      title: title,
      body: body,
      campaignRoomId: campaignRoomId,
      createdAt: DateTime.now(),
      metadata: metadata,
    );
    _notifications[notification.id] = notification;
  }

  Friendship? _relationship(String a, String b) => _friendships.values
      .where((value) => value.involves(a) && value.involves(b))
      .firstOrNull;

  bool _isBlocked(String a, String b) {
    final relationship = _relationship(a, b);
    return relationship?.status == FriendshipStatus.blocked;
  }

  UserAccount _publicAccount(UserAccount account) => account.copyWith(
    presence: account.hidePresence ? PresenceStatus.offline : account.presence,
    settings: const {},
  );

  String _normalizeHandle(String handle) {
    final value = handle.trim().toLowerCase().replaceFirst('@', '');
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(value)) {
      throw FormatException('用户 ID 仅支持 3~24 位小写字母、数字和下划线');
    }
    return value;
  }

  void _validatePassword(String password) {
    if (password.length < 8 || password.length > 128) {
      throw FormatException('密码长度必须为 8~128 位');
    }
  }

  String _token() => base64UrlEncode(
    List<int>.generate(48, (_) => _random.nextInt(256)),
  ).replaceAll('=', '');

  String _hashToken(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  String _shortCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(8, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  File get _stateFile =>
      File('$directory${Platform.pathSeparator}social_state.json');

  Future<void> _persist() {
    final previous = _writeQueue;
    final completer = Completer<void>();
    _writeQueue = completer.future;
    return previous.then((_) async {
      try {
        final file = _stateFile;
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'accounts': _accounts.values
                .map(
                  (value) => {
                    ...value.toJson(),
                    'passwordHash': _passwordHashes[value.userId],
                  },
                )
                .toList(),
            'devices': _devices.values.map((value) => value.toJson()).toList(),
            'friendships': _friendships.values
                .map((value) => value.toJson())
                .toList(),
            'invites': _invites.values.map((value) => value.toJson()).toList(),
            'campaigns': _campaigns.values
                .map((value) => value.toJson())
                .toList(),
            'notifications': _notifications.values
                .map((value) => value.toJson())
                .toList(),
            'recentPlayers': _recentPlayers.map(
              (key, value) => MapEntry(key, value.toList()),
            ),
          }),
          flush: true,
        );
        if (await file.exists()) await file.delete();
        await temp.rename(file.path);
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
        rethrow;
      }
    });
  }
}

class SlidingWindowRateLimiter {
  SlidingWindowRateLimiter({required this.limit, required this.window});
  final int limit;
  final Duration window;
  final _attempts = <String, List<DateTime>>{};

  bool allow(String key) {
    final now = DateTime.now();
    final cutoff = now.subtract(window);
    final values = _attempts.putIfAbsent(key, () => [])
      ..removeWhere((value) => value.isBefore(cutoff));
    if (values.length >= limit) return false;
    values.add(now);
    return true;
  }
}
