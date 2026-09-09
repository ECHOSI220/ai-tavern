import 'dart:convert';
import 'dart:io';

import 'package:ai_tavern/models/social_models.dart';
import 'package:ai_tavern/services/trpg/room_permission_service.dart';
import 'package:ai_tavern/services/trpg/social_backend_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TRPG Phase 7 account and persistent campaign', () {
    late Directory directory;
    late SocialBackendService backend;
    late AuthTokens alice;
    late AuthTokens bob;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('tavern_phase7_');
      backend = SocialBackendService(directory: directory.path);
      await backend.initialize();
      alice = await backend.register(
        handle: 'alice_pc',
        displayName: '艾丽丝',
        password: 'safe-pass-123',
        deviceName: 'Alice PC',
        platform: 'windows',
      );
      bob = await backend.register(
        handle: 'bob_phone',
        displayName: '鲍勃',
        password: 'safe-pass-456',
        deviceName: 'Bob Phone',
        platform: 'android',
      );
    });

    tearDown(() => directory.delete(recursive: true));

    test(
      'passwords and bearer tokens are never persisted in plaintext',
      () async {
        final state = await File(
          '${directory.path}${Platform.pathSeparator}social_state.json',
        ).readAsString();
        expect(state, isNot(contains('safe-pass-123')));
        expect(state, isNot(contains(alice.accessToken)));
        expect(state, isNot(contains(alice.refreshToken)));
        final json = jsonDecode(state) as Map<String, Object?>;
        final account = (json['accounts'] as List).first as Map;
        expect(account['passwordHash'], startsWith(r'$2'));
      },
    );

    test(
      'friend request, acceptance and block are server authoritative',
      () async {
        final request = await backend.requestFriend(
          alice.account.userId,
          bob.account.handle,
        );
        await backend.respondFriend(
          bob.account.userId,
          request.id,
          accept: true,
        );
        expect(
          backend.friends(alice.account.userId).single['account'],
          isA<Map<String, Object?>>(),
        );
        await backend.block(alice.account.userId, bob.account.userId);
        expect(
          backend.friends(alice.account.userId).single['friendship']
              as Map<String, Object?>,
          containsPair('status', FriendshipStatus.blocked.name),
        );
      },
    );

    test('campaign membership and character binding survive restart', () async {
      final room = await backend.createCampaign(
        ownerUserId: alice.account.userId,
        campaignId: 'mist_harbor_test',
        title: '雾港长期团',
      );
      final invite = await backend.inviteCampaign(
        alice.account.userId,
        room.id,
        bob.account.handle,
      );
      var joined = await backend.respondCampaignInvite(
        bob.account.userId,
        invite.id,
        accept: true,
      );
      joined = await backend.bindCharacter(
        bob.account.userId,
        room.id,
        'investigator_b',
        expectedRevision: joined.revision,
      );
      expect(joined.member(bob.account.userId)?.characterId, 'investigator_b');

      final restored = SocialBackendService(directory: directory.path);
      await restored.initialize();
      final secondDevice = await restored.login(
        handle: alice.account.handle,
        password: 'safe-pass-123',
        deviceName: 'Alice Android',
        platform: 'android',
      );
      expect(restored.devices(alice.account.userId), hasLength(2));
      expect(
        restored.campaignsFor(secondDevice.account.userId).single.id,
        room.id,
      );
      expect(
        restored
            .campaignFor(bob.account.userId, room.id)
            .member(bob.account.userId)
            ?.characterId,
        'investigator_b',
      );
    });

    test('revision conflicts prevent stale cross-device overwrite', () async {
      final room = await backend.createCampaign(
        ownerUserId: alice.account.userId,
        campaignId: 'mist_harbor_test',
        title: '冲突测试',
      );
      await backend.bindCharacter(
        alice.account.userId,
        room.id,
        'character_a',
        expectedRevision: room.revision,
      );
      expect(
        () => backend.bindCharacter(
          alice.account.userId,
          room.id,
          'character_b',
          expectedRevision: room.revision,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('admin can start but cannot delete or transfer ownership', () async {
      var room = await backend.createCampaign(
        ownerUserId: alice.account.userId,
        campaignId: 'mist_harbor_test',
        title: '权限测试',
      );
      final invite = await backend.inviteCampaign(
        alice.account.userId,
        room.id,
        bob.account.handle,
      );
      room = await backend.respondCampaignInvite(
        bob.account.userId,
        invite.id,
        accept: true,
      );
      room = await backend.setMemberRole(
        alice.account.userId,
        room.id,
        bob.account.userId,
        CampaignMemberRole.admin,
      );
      const permissions = RoomPermissionService();
      expect(
        permissions.can(room, bob.account.userId, RoomPermission.start),
        isTrue,
      );
      expect(
        permissions.can(room, bob.account.userId, RoomPermission.delete),
        isFalse,
      );
      expect(
        permissions.can(
          room,
          bob.account.userId,
          RoomPermission.transferOwnership,
        ),
        isFalse,
      );
    });

    test('ownership transfer requires recipient confirmation', () async {
      var room = await backend.createCampaign(
        ownerUserId: alice.account.userId,
        campaignId: 'mist_harbor_test',
        title: '转移确认',
      );
      final join = await backend.inviteCampaign(
        alice.account.userId,
        room.id,
        bob.account.handle,
      );
      room = await backend.respondCampaignInvite(
        bob.account.userId,
        join.id,
        accept: true,
      );
      final transfer = await backend.requestOwnershipTransfer(
        alice.account.userId,
        room.id,
        bob.account.userId,
      );
      expect(
        backend.inspectCampaign(room.id)?.ownerUserId,
        alice.account.userId,
      );
      room = await backend.respondOwnershipTransfer(
        bob.account.userId,
        transfer.id,
        accept: true,
      );
      expect(room.ownerUserId, bob.account.userId);
      expect(room.member(bob.account.userId)?.role, CampaignMemberRole.owner);
      expect(room.member(alice.account.userId)?.role, CampaignMemberRole.admin);
    });

    test(
      'removed member history is retained and banned member cannot rejoin',
      () async {
        var room = await backend.createCampaign(
          ownerUserId: alice.account.userId,
          campaignId: 'mist_harbor_test',
          title: '成员管理',
        );
        final firstInvite = await backend.inviteCampaign(
          alice.account.userId,
          room.id,
          bob.account.handle,
        );
        room = await backend.respondCampaignInvite(
          bob.account.userId,
          firstInvite.id,
          accept: true,
        );
        room = await backend.bindCharacter(
          bob.account.userId,
          room.id,
          'retained-character',
          expectedRevision: room.revision,
        );
        room = await backend.manageMember(
          alice.account.userId,
          room.id,
          bob.account.userId,
          ban: true,
        );
        expect(
          room.member(bob.account.userId)?.characterId,
          'retained-character',
        );
        expect(
          room.member(bob.account.userId)?.status,
          MembershipStatus.banned,
        );
        expect(
          () => backend.inviteCampaign(
            alice.account.userId,
            room.id,
            bob.account.handle,
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('play sessions, archive, summary and backups persist', () async {
      var room = await backend.createCampaign(
        ownerUserId: alice.account.userId,
        campaignId: 'mist_harbor_test',
        title: '历史测试',
      );
      room = await backend.startPlaySession(
        room.id,
        sessionId: 'session-1',
        participantUserIds: [alice.account.userId],
        startingRevision: room.revision,
      );
      room = await backend.endPlaySession(
        room.id,
        endingRevision: room.revision,
      );
      expect(room.playSessions.single.endedAt, isNotNull);
      final backupId = await backend.createBackup(
        alice.account.userId,
        room.id,
        {
          'sessionId': 'session-1',
          'memoryState': {'entries': []},
        },
      );
      final restored = await backend.restoreBackup(
        alice.account.userId,
        room.id,
        backupId,
      );
      expect(restored['sessionId'], 'session-1');
      final archived = await backend.archive(
        alice.account.userId,
        room.id,
        finalSummary: '成功破获雾港疑案',
      );
      expect(archived.lifecycle, CampaignRoomLifecycle.archived);
      expect(archived.finalSummary, contains('雾港'));
    });
  });
}
