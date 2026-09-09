enum AccountStatus { active, disabled, deleted }

enum PresenceStatus { online, away, offline, inSession }

enum FriendshipStatus { pending, accepted, blocked, removed }

enum SocialInviteType {
  friendRequest,
  roomInvite,
  campaignInvite,
  ownershipTransfer,
}

enum InviteStatus { pending, accepted, declined, expired, revoked }

enum CampaignRoomKind { temporary, persistent }

enum CampaignRoomPrivacy { private, inviteOnly, codeJoin }

enum CampaignMemberRole { owner, admin, player, humanGm, spectator }

enum MembershipStatus { invited, active, inactive, left, removed, banned }

enum CampaignRoomLifecycle {
  idle,
  active,
  paused,
  completed,
  archived,
  deleted,
}

enum RsvpStatus { unknown, attending, uncertain, absent }

enum InvitePermission { ownerOnly, admins, allMembers }

enum NotificationType {
  friendRequest,
  friendAccepted,
  campaignInvite,
  joinRequest,
  campaignStarted,
  hostRequest,
  hostOffline,
  campaignResume,
  announcement,
}

T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((value) => value.name == raw).firstOrNull ?? fallback;

List<String> _strings(Object? raw) =>
    raw is List ? raw.map((value) => value.toString()).toList() : const [];

Map<String, Object?> _map(Object? raw) => raw is Map
    ? raw.map((key, value) => MapEntry(key.toString(), value))
    : const {};

class UserAccount {
  const UserAccount({
    required this.userId,
    required this.handle,
    required this.displayName,
    required this.createdAt,
    required this.lastOnlineAt,
    this.avatar,
    this.status = AccountStatus.active,
    this.presence = PresenceStatus.offline,
    this.hidePresence = false,
    this.settings = const {},
  });
  final String userId, handle, displayName;
  final String? avatar;
  final DateTime createdAt, lastOnlineAt;
  final AccountStatus status;
  final PresenceStatus presence;
  final bool hidePresence;
  final Map<String, Object?> settings;

  UserAccount copyWith({
    String? displayName,
    String? avatar,
    DateTime? lastOnlineAt,
    AccountStatus? status,
    PresenceStatus? presence,
    bool? hidePresence,
    Map<String, Object?>? settings,
  }) => UserAccount(
    userId: userId,
    handle: handle,
    displayName: displayName ?? this.displayName,
    avatar: avatar ?? this.avatar,
    createdAt: createdAt,
    lastOnlineAt: lastOnlineAt ?? this.lastOnlineAt,
    status: status ?? this.status,
    presence: presence ?? this.presence,
    hidePresence: hidePresence ?? this.hidePresence,
    settings: settings ?? this.settings,
  );

  Map<String, Object?> toJson() => {
    'userId': userId,
    'handle': handle,
    'displayName': displayName,
    'avatar': avatar,
    'createdAt': createdAt.toIso8601String(),
    'lastOnlineAt': lastOnlineAt.toIso8601String(),
    'status': status.name,
    'presence': presence.name,
    'hidePresence': hidePresence,
    'settings': settings,
  };

  factory UserAccount.fromJson(Map<String, Object?> json) => UserAccount(
    userId: json['userId'] as String? ?? '',
    handle: json['handle'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    avatar: json['avatar'] as String?,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    lastOnlineAt:
        DateTime.tryParse(json['lastOnlineAt'] as String? ?? '') ??
        DateTime.now(),
    status: _enum(AccountStatus.values, json['status'], AccountStatus.active),
    presence: _enum(
      PresenceStatus.values,
      json['presence'],
      PresenceStatus.offline,
    ),
    hidePresence: json['hidePresence'] as bool? ?? false,
    settings: _map(json['settings']),
  );
}

class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.userId,
    required this.deviceName,
    required this.platform,
    required this.tokenHash,
    required this.refreshTokenHash,
    required this.createdAt,
    required this.expiresAt,
    required this.refreshExpiresAt,
    required this.lastSeenAt,
    this.revoked = false,
    this.supportsAIHost = false,
    this.providerTypes = const [],
    this.toolCallingVerified = false,
  });
  final String id, userId, deviceName, platform, tokenHash, refreshTokenHash;
  final DateTime createdAt, expiresAt, refreshExpiresAt, lastSeenAt;
  final bool revoked, supportsAIHost, toolCallingVerified;
  final List<String> providerTypes;
  Map<String, Object?> toJson() => {
    'id': id,
    'userId': userId,
    'deviceName': deviceName,
    'platform': platform,
    'tokenHash': tokenHash,
    'refreshTokenHash': refreshTokenHash,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'refreshExpiresAt': refreshExpiresAt.toIso8601String(),
    'lastSeenAt': lastSeenAt.toIso8601String(),
    'revoked': revoked,
    'supportsAIHost': supportsAIHost,
    'providerTypes': providerTypes,
    'toolCallingVerified': toolCallingVerified,
  };
  factory DeviceSession.fromJson(Map<String, Object?> json) => DeviceSession(
    id: json['id'] as String? ?? '',
    userId: json['userId'] as String? ?? '',
    deviceName: json['deviceName'] as String? ?? '',
    platform: json['platform'] as String? ?? '',
    tokenHash: json['tokenHash'] as String? ?? '',
    refreshTokenHash: json['refreshTokenHash'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    refreshExpiresAt: DateTime.parse(json['refreshExpiresAt'] as String),
    lastSeenAt: DateTime.parse(json['lastSeenAt'] as String),
    revoked: json['revoked'] as bool? ?? false,
    supportsAIHost: json['supportsAIHost'] as bool? ?? false,
    providerTypes: _strings(json['providerTypes']),
    toolCallingVerified: json['toolCallingVerified'] as bool? ?? false,
  );
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.account,
    required this.deviceSessionId,
  });
  final String accessToken, refreshToken, deviceSessionId;
  final DateTime expiresAt;
  final UserAccount account;
  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
    'account': account.toJson(),
    'deviceSessionId': deviceSessionId,
  };
  factory AuthTokens.fromJson(Map<String, Object?> json) => AuthTokens(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    account: UserAccount.fromJson(
      (json['account'] as Map).cast<String, Object?>(),
    ),
    deviceSessionId: json['deviceSessionId'] as String,
  );
}

class Friendship {
  const Friendship({
    required this.id,
    required this.requesterUserId,
    required this.addresseeUserId,
    required this.createdAt,
    required this.updatedAt,
    this.status = FriendshipStatus.pending,
  });
  final String id, requesterUserId, addresseeUserId;
  final FriendshipStatus status;
  final DateTime createdAt, updatedAt;
  bool involves(String userId) =>
      requesterUserId == userId || addresseeUserId == userId;
  String other(String userId) =>
      requesterUserId == userId ? addresseeUserId : requesterUserId;
  Friendship copyWith({FriendshipStatus? status, DateTime? updatedAt}) =>
      Friendship(
        id: id,
        requesterUserId: requesterUserId,
        addresseeUserId: addresseeUserId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        status: status ?? this.status,
      );
  Map<String, Object?> toJson() => {
    'id': id,
    'requesterUserId': requesterUserId,
    'addresseeUserId': addresseeUserId,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory Friendship.fromJson(Map<String, Object?> json) => Friendship(
    id: json['id'] as String,
    requesterUserId: json['requesterUserId'] as String,
    addresseeUserId: json['addresseeUserId'] as String,
    status: _enum(
      FriendshipStatus.values,
      json['status'],
      FriendshipStatus.pending,
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

class SocialInvite {
  const SocialInvite({
    required this.id,
    required this.type,
    required this.senderUserId,
    required this.recipientUserId,
    required this.createdAt,
    required this.expiresAt,
    this.campaignRoomId,
    this.status = InviteStatus.pending,
    this.code,
  });
  final String id, senderUserId, recipientUserId;
  final SocialInviteType type;
  final String? campaignRoomId, code;
  final InviteStatus status;
  final DateTime createdAt, expiresAt;
  SocialInvite copyWith({InviteStatus? status}) => SocialInvite(
    id: id,
    type: type,
    senderUserId: senderUserId,
    recipientUserId: recipientUserId,
    campaignRoomId: campaignRoomId,
    status: status ?? this.status,
    code: code,
    createdAt: createdAt,
    expiresAt: expiresAt,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'senderUserId': senderUserId,
    'recipientUserId': recipientUserId,
    'campaignRoomId': campaignRoomId,
    'status': status.name,
    'code': code,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };
  factory SocialInvite.fromJson(Map<String, Object?> json) => SocialInvite(
    id: json['id'] as String,
    type: _enum(
      SocialInviteType.values,
      json['type'],
      SocialInviteType.campaignInvite,
    ),
    senderUserId: json['senderUserId'] as String,
    recipientUserId: json['recipientUserId'] as String,
    campaignRoomId: json['campaignRoomId'] as String?,
    status: _enum(InviteStatus.values, json['status'], InviteStatus.pending),
    code: json['code'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}

class CampaignMember {
  const CampaignMember({
    required this.userId,
    required this.roomPlayerId,
    required this.role,
    required this.joinedAt,
    required this.lastPlayedAt,
    this.characterId,
    this.roomNickname,
    this.status = MembershipStatus.active,
    this.rsvp = RsvpStatus.unknown,
    this.permissions = const [],
  });
  final String userId, roomPlayerId;
  final CampaignMemberRole role;
  final String? characterId, roomNickname;
  final DateTime joinedAt, lastPlayedAt;
  final MembershipStatus status;
  final RsvpStatus rsvp;
  final List<String> permissions;
  CampaignMember copyWith({
    CampaignMemberRole? role,
    String? characterId,
    String? roomNickname,
    DateTime? lastPlayedAt,
    MembershipStatus? status,
    RsvpStatus? rsvp,
    List<String>? permissions,
  }) => CampaignMember(
    userId: userId,
    roomPlayerId: roomPlayerId,
    role: role ?? this.role,
    characterId: characterId ?? this.characterId,
    roomNickname: roomNickname ?? this.roomNickname,
    joinedAt: joinedAt,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    status: status ?? this.status,
    rsvp: rsvp ?? this.rsvp,
    permissions: permissions ?? this.permissions,
  );
  Map<String, Object?> toJson() => {
    'userId': userId,
    'roomPlayerId': roomPlayerId,
    'role': role.name,
    'characterId': characterId,
    'roomNickname': roomNickname,
    'joinedAt': joinedAt.toIso8601String(),
    'lastPlayedAt': lastPlayedAt.toIso8601String(),
    'status': status.name,
    'rsvp': rsvp.name,
    'permissions': permissions,
  };
  factory CampaignMember.fromJson(Map<String, Object?> json) => CampaignMember(
    userId: json['userId'] as String,
    roomPlayerId: json['roomPlayerId'] as String,
    role: _enum(
      CampaignMemberRole.values,
      json['role'],
      CampaignMemberRole.player,
    ),
    characterId: json['characterId'] as String?,
    roomNickname: json['roomNickname'] as String?,
    joinedAt: DateTime.parse(json['joinedAt'] as String),
    lastPlayedAt: DateTime.parse(json['lastPlayedAt'] as String),
    status: _enum(
      MembershipStatus.values,
      json['status'],
      MembershipStatus.active,
    ),
    rsvp: _enum(RsvpStatus.values, json['rsvp'], RsvpStatus.unknown),
    permissions: _strings(json['permissions']),
  );
}

class DeviceAIProviderCapability {
  const DeviceAIProviderCapability({
    required this.userId,
    required this.connectionId,
    required this.deviceSessionId,
    required this.updatedAt,
    this.supportsAIHost = false,
    this.providerTypes = const [],
    this.toolCallingVerified = false,
    this.autoAcceptForCampaign = false,
  });
  final String userId, connectionId, deviceSessionId;
  final bool supportsAIHost, toolCallingVerified, autoAcceptForCampaign;
  final List<String> providerTypes;
  final DateTime updatedAt;
  Map<String, Object?> toJson() => {
    'userId': userId,
    'connectionId': connectionId,
    'deviceSessionId': deviceSessionId,
    'supportsAIHost': supportsAIHost,
    'providerTypes': providerTypes,
    'toolCallingVerified': toolCallingVerified,
    'autoAcceptForCampaign': autoAcceptForCampaign,
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory DeviceAIProviderCapability.fromJson(Map<String, Object?> json) =>
      DeviceAIProviderCapability(
        userId: json['userId'] as String,
        connectionId: json['connectionId'] as String,
        deviceSessionId: json['deviceSessionId'] as String,
        supportsAIHost: json['supportsAIHost'] as bool? ?? false,
        providerTypes: _strings(json['providerTypes']),
        toolCallingVerified: json['toolCallingVerified'] as bool? ?? false,
        autoAcceptForCampaign: json['autoAcceptForCampaign'] as bool? ?? false,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class AIHostPolicy {
  const AIHostPolicy({
    this.preferredProviderUserId,
    this.backupProviderUserIds = const [],
    this.allowOwnerFallback = true,
    this.serverFallback = false,
  });
  final String? preferredProviderUserId;
  final List<String> backupProviderUserIds;
  final bool allowOwnerFallback, serverFallback;
  Map<String, Object?> toJson() => {
    'preferredProviderUserId': preferredProviderUserId,
    'backupProviderUserIds': backupProviderUserIds,
    'allowOwnerFallback': allowOwnerFallback,
    'serverFallback': serverFallback,
  };
  factory AIHostPolicy.fromJson(Map<String, Object?> json) => AIHostPolicy(
    preferredProviderUserId: json['preferredProviderUserId'] as String?,
    backupProviderUserIds: _strings(json['backupProviderUserIds']),
    allowOwnerFallback: json['allowOwnerFallback'] as bool? ?? true,
    serverFallback: json['serverFallback'] as bool? ?? false,
  );
}

class CampaignHistoryEntry {
  const CampaignHistoryEntry({
    required this.id,
    required this.type,
    required this.message,
    required this.createdAt,
    this.actorUserId,
    this.metadata = const {},
  });
  final String id, type, message;
  final String? actorUserId;
  final DateTime createdAt;
  final Map<String, Object?> metadata;
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'message': message,
    'actorUserId': actorUserId,
    'createdAt': createdAt.toIso8601String(),
    'metadata': metadata,
  };
  factory CampaignHistoryEntry.fromJson(Map<String, Object?> json) =>
      CampaignHistoryEntry(
        id: json['id'] as String,
        type: json['type'] as String,
        message: json['message'] as String,
        actorUserId: json['actorUserId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        metadata: _map(json['metadata']),
      );
}

class PlaySessionRecord {
  const PlaySessionRecord({
    required this.id,
    required this.campaignRoomId,
    required this.startedAt,
    required this.participants,
    required this.startingRevision,
    this.endedAt,
    this.endingRevision,
  });
  final String id, campaignRoomId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<String> participants;
  final int startingRevision;
  final int? endingRevision;
  Map<String, Object?> toJson() => {
    'id': id,
    'campaignRoomId': campaignRoomId,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'participants': participants,
    'startingRevision': startingRevision,
    'endingRevision': endingRevision,
  };
  factory PlaySessionRecord.fromJson(Map<String, Object?> json) =>
      PlaySessionRecord(
        id: json['id'] as String,
        campaignRoomId: json['campaignRoomId'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
        participants: _strings(json['participants']),
        startingRevision: (json['startingRevision'] as num?)?.toInt() ?? 0,
        endingRevision: (json['endingRevision'] as num?)?.toInt(),
      );
}

class CampaignNotification {
  const CampaignNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.campaignRoomId,
    this.read = false,
    this.metadata = const {},
  });
  final String id, userId, title, body;
  final NotificationType type;
  final String? campaignRoomId;
  final DateTime createdAt;
  final bool read;
  final Map<String, Object?> metadata;
  CampaignNotification copyWith({bool? read}) => CampaignNotification(
    id: id,
    userId: userId,
    type: type,
    title: title,
    body: body,
    campaignRoomId: campaignRoomId,
    createdAt: createdAt,
    read: read ?? this.read,
    metadata: metadata,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'userId': userId,
    'type': type.name,
    'title': title,
    'body': body,
    'campaignRoomId': campaignRoomId,
    'createdAt': createdAt.toIso8601String(),
    'read': read,
    'metadata': metadata,
  };
  factory CampaignNotification.fromJson(Map<String, Object?> json) =>
      CampaignNotification(
        id: json['id'] as String,
        userId: json['userId'] as String,
        type: _enum(
          NotificationType.values,
          json['type'],
          NotificationType.campaignResume,
        ),
        title: json['title'] as String,
        body: json['body'] as String,
        campaignRoomId: json['campaignRoomId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        read: json['read'] as bool? ?? false,
        metadata: _map(json['metadata']),
      );
}

class PersistentCampaignRoom {
  const PersistentCampaignRoom({
    required this.id,
    required this.campaignId,
    required this.ownerUserId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.lastPlayedAt,
    this.description = '',
    this.cover,
    this.sessionId,
    this.inviteCode,
    this.kind = CampaignRoomKind.persistent,
    this.privacy = CampaignRoomPrivacy.inviteOnly,
    this.lifecycle = CampaignRoomLifecycle.idle,
    this.members = const [],
    this.maxMembers = 6,
    this.minimumPlayersToStart = 1,
    this.ownerApprovalRequired = false,
    this.allowGuests = false,
    this.allowCharacterChange = false,
    this.invitePermission = InvitePermission.admins,
    this.aiHostPolicy = const AIHostPolicy(),
    this.announcement = '',
    this.nextSessionAt,
    this.history = const [],
    this.playSessions = const [],
    this.bannedUserIds = const [],
    this.finalSummary = '',
    this.revision = 0,
    this.deletedAt,
  });
  final String id, campaignId, ownerUserId, title, description;
  final String? cover, sessionId, inviteCode;
  final CampaignRoomKind kind;
  final CampaignRoomPrivacy privacy;
  final CampaignRoomLifecycle lifecycle;
  final List<CampaignMember> members;
  final int maxMembers, minimumPlayersToStart, revision;
  final bool ownerApprovalRequired, allowGuests, allowCharacterChange;
  final InvitePermission invitePermission;
  final AIHostPolicy aiHostPolicy;
  final String announcement, finalSummary;
  final DateTime createdAt, updatedAt, lastPlayedAt;
  final DateTime? nextSessionAt, deletedAt;
  final List<CampaignHistoryEntry> history;
  final List<PlaySessionRecord> playSessions;
  final List<String> bannedUserIds;
  bool hasMember(String userId) => members.any(
    (value) =>
        value.userId == userId && value.status == MembershipStatus.active,
  );
  CampaignMember? member(String userId) =>
      members.where((value) => value.userId == userId).firstOrNull;
  PersistentCampaignRoom copyWith({
    String? ownerUserId,
    String? title,
    String? description,
    String? cover,
    String? sessionId,
    String? inviteCode,
    CampaignRoomPrivacy? privacy,
    CampaignRoomLifecycle? lifecycle,
    List<CampaignMember>? members,
    int? maxMembers,
    int? minimumPlayersToStart,
    bool? ownerApprovalRequired,
    bool? allowGuests,
    bool? allowCharacterChange,
    InvitePermission? invitePermission,
    AIHostPolicy? aiHostPolicy,
    String? announcement,
    DateTime? nextSessionAt,
    List<CampaignHistoryEntry>? history,
    List<PlaySessionRecord>? playSessions,
    List<String>? bannedUserIds,
    String? finalSummary,
    int? revision,
    DateTime? updatedAt,
    DateTime? lastPlayedAt,
    DateTime? deletedAt,
  }) => PersistentCampaignRoom(
    id: id,
    campaignId: campaignId,
    ownerUserId: ownerUserId ?? this.ownerUserId,
    title: title ?? this.title,
    description: description ?? this.description,
    cover: cover ?? this.cover,
    sessionId: sessionId ?? this.sessionId,
    inviteCode: inviteCode ?? this.inviteCode,
    kind: kind,
    privacy: privacy ?? this.privacy,
    lifecycle: lifecycle ?? this.lifecycle,
    members: members ?? this.members,
    maxMembers: maxMembers ?? this.maxMembers,
    minimumPlayersToStart: minimumPlayersToStart ?? this.minimumPlayersToStart,
    ownerApprovalRequired: ownerApprovalRequired ?? this.ownerApprovalRequired,
    allowGuests: allowGuests ?? this.allowGuests,
    allowCharacterChange: allowCharacterChange ?? this.allowCharacterChange,
    invitePermission: invitePermission ?? this.invitePermission,
    aiHostPolicy: aiHostPolicy ?? this.aiHostPolicy,
    announcement: announcement ?? this.announcement,
    nextSessionAt: nextSessionAt ?? this.nextSessionAt,
    history: history ?? this.history,
    playSessions: playSessions ?? this.playSessions,
    bannedUserIds: bannedUserIds ?? this.bannedUserIds,
    finalSummary: finalSummary ?? this.finalSummary,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'campaignId': campaignId,
    'ownerUserId': ownerUserId,
    'title': title,
    'description': description,
    'cover': cover,
    'sessionId': sessionId,
    'inviteCode': inviteCode,
    'kind': kind.name,
    'privacy': privacy.name,
    'lifecycle': lifecycle.name,
    'members': members.map((value) => value.toJson()).toList(),
    'maxMembers': maxMembers,
    'minimumPlayersToStart': minimumPlayersToStart,
    'ownerApprovalRequired': ownerApprovalRequired,
    'allowGuests': allowGuests,
    'allowCharacterChange': allowCharacterChange,
    'invitePermission': invitePermission.name,
    'aiHostPolicy': aiHostPolicy.toJson(),
    'announcement': announcement,
    'nextSessionAt': nextSessionAt?.toIso8601String(),
    'history': history.map((value) => value.toJson()).toList(),
    'playSessions': playSessions.map((value) => value.toJson()).toList(),
    'bannedUserIds': bannedUserIds,
    'finalSummary': finalSummary,
    'revision': revision,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastPlayedAt': lastPlayedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };
  factory PersistentCampaignRoom.fromJson(
    Map<String, Object?> json,
  ) => PersistentCampaignRoom(
    id: json['id'] as String,
    campaignId: json['campaignId'] as String,
    ownerUserId: json['ownerUserId'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    cover: json['cover'] as String?,
    sessionId: json['sessionId'] as String?,
    inviteCode: json['inviteCode'] as String?,
    kind: _enum(
      CampaignRoomKind.values,
      json['kind'],
      CampaignRoomKind.persistent,
    ),
    privacy: _enum(
      CampaignRoomPrivacy.values,
      json['privacy'],
      CampaignRoomPrivacy.inviteOnly,
    ),
    lifecycle: _enum(
      CampaignRoomLifecycle.values,
      json['lifecycle'],
      CampaignRoomLifecycle.idle,
    ),
    members: (json['members'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => CampaignMember.fromJson(value.cast<String, Object?>()))
        .toList(),
    maxMembers: (json['maxMembers'] as num?)?.toInt() ?? 6,
    minimumPlayersToStart:
        (json['minimumPlayersToStart'] as num?)?.toInt() ?? 1,
    ownerApprovalRequired: json['ownerApprovalRequired'] as bool? ?? false,
    allowGuests: json['allowGuests'] as bool? ?? false,
    allowCharacterChange: json['allowCharacterChange'] as bool? ?? false,
    invitePermission: _enum(
      InvitePermission.values,
      json['invitePermission'],
      InvitePermission.admins,
    ),
    aiHostPolicy: AIHostPolicy.fromJson(
      (json['aiHostPolicy'] as Map? ?? const {}).cast<String, Object?>(),
    ),
    announcement: json['announcement'] as String? ?? '',
    nextSessionAt: DateTime.tryParse(json['nextSessionAt'] as String? ?? ''),
    history: (json['history'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              CampaignHistoryEntry.fromJson(value.cast<String, Object?>()),
        )
        .toList(),
    playSessions: (json['playSessions'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => PlaySessionRecord.fromJson(value.cast<String, Object?>()),
        )
        .toList(),
    bannedUserIds: _strings(json['bannedUserIds']),
    finalSummary: json['finalSummary'] as String? ?? '',
    revision: (json['revision'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    lastPlayedAt: DateTime.parse(json['lastPlayedAt'] as String),
    deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
  );
}
