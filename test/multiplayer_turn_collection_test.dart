import 'dart:async';
import 'dart:io';

import 'package:ai_tavern/models/multiplayer_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/services/ai/openai_compatible_provider.dart';
import 'package:ai_tavern/services/trpg/multiplayer_server.dart';
import 'package:ai_tavern/services/trpg/multiplayer_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'freeform round waits for everyone, resolves once, and keeps actors separate',
    () async {
      final data = await Directory.systemTemp.createTemp('turn-collection-');
      final server = MultiplayerAuthoritativeServer(
        config: MultiplayerServerConfig(
          address: '127.0.0.1',
          port: 0,
          persistenceDirectory: data.path,
          aiRequestTimeout: const Duration(seconds: 5),
          settlementGrace: const Duration(milliseconds: 80),
        ),
      );
      await server.start();
      final endpoint = 'ws://127.0.0.1:${server.port}/ws';
      final alice = MultiplayerClient();
      final bob = MultiplayerClient();
      final aliceEvents = <MultiplayerEnvelope>[];
      final bobEvents = <MultiplayerEnvelope>[];
      alice.events.listen(aliceEvents.add);
      bob.events.listen(bobEvents.add);
      addTearDown(() async {
        await alice.close();
        await bob.close();
        await server.stop();
        await data.delete(recursive: true);
      });

      final createdFuture = alice.states.first;
      await alice.createRoom(
        endpoint: endpoint,
        roomName: '同步行动测试',
        playerName: 'Alice',
      );
      final created = await createdFuture;
      final joinedFuture = bob.states.first;
      await bob.joinRoom(
        endpoint: endpoint,
        roomCode: created.room.roomCode,
        playerName: 'Bob',
      );
      await joinedFuture;
      await _waitUntil(() => alice.snapshot?.room.players.length == 2);

      await alice.selectCharacter(
        _character(alice.credentials!.playerId, 'alice-character', '亚瑟'),
      );
      await bob.selectCharacter(
        _character(bob.credentials!.playerId, 'bob-character', '莉娜'),
      );
      await alice.setReady(true);
      await bob.setReady(true);
      await _waitUntil(
        () => alice.snapshot!.room.players.every(
          (player) => player.isReady && player.characterId != null,
        ),
      );
      await alice.requestHost(
        bob.credentials!.playerId,
        modelId: 'turn-test-model',
      );
      await bob.acceptHost(modelId: 'turn-test-model');
      await _waitUntil(
        () => alice.snapshot!.room.aiHostConfig.status == AIHostStatus.ready,
      );

      final openingFuture = bob.events.firstWhere(
        (event) => event.type == MultiplayerEventType.aiRequest,
      );
      await alice.startGame();
      final opening = await openingFuture;
      await bob.sendAIResponse(
        requestId: opening.payload['requestId'] as String,
        response: const OpenAIChatResponse(
          content: '两名调查者站在大厅中央。',
          toolCalls: [],
        ).toJson(),
      );
      await _waitUntil(
        () =>
            alice.snapshot?.room.currentTurn?.phase ==
            MultiplayerTurnPhase.collecting,
      );

      aliceEvents.clear();
      bobEvents.clear();
      final turn = alice.snapshot!.room.currentTurn!;
      const aliceActionId = 'turn-left-alice';
      const bobActionId = 'turn-right-bob';

      await alice.confirmTurnAction(
        turnId: turn.turnId,
        content: '我向左侧走廊移动。',
        actionId: aliceActionId,
      );
      await _waitUntil(
        () => bob.snapshot!.room.currentTurn!.confirmedPlayerIds.contains(
          alice.credentials!.playerId,
        ),
      );
      expect(
        bob
            .snapshot!
            .room
            .currentTurn!
            .playerActions[alice.credentials!.playerId]!
            .content,
        isEmpty,
        reason: '其他玩家只能看到确认状态，不能偷看行动内容',
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(
        bobEvents.where(
          (event) => event.type == MultiplayerEventType.aiRequest,
        ),
        isEmpty,
        reason: '只有 Alice 确认时绝不能调用 AI',
      );

      await alice.unconfirmTurnAction(turn.turnId);
      await _waitUntil(
        () => !alice.snapshot!.room.currentTurn!.confirmedPlayerIds.contains(
          alice.credentials!.playerId,
        ),
      );
      await alice.confirmTurnAction(
        turnId: turn.turnId,
        content: '我进入左侧走廊并观察墙面。',
        actionId: aliceActionId,
      );
      await alice.confirmTurnAction(
        turnId: turn.turnId,
        content: '网络重试不应产生第二份行动',
        actionId: aliceActionId,
      );

      final resolutionFuture = bob.events.firstWhere(
        (event) => event.type == MultiplayerEventType.aiRequest,
      );
      await bob.confirmTurnAction(
        turnId: turn.turnId,
        content: '我去右侧诊室检查。',
        actionId: bobActionId,
      );
      await bob.confirmTurnAction(
        turnId: turn.turnId,
        content: '重复确认',
        actionId: bobActionId,
      );
      final resolution = await resolutionFuture;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(
        bobEvents.where(
          (event) => event.type == MultiplayerEventType.aiRequest,
        ),
        hasLength(1),
        reason: '同一 turnId 只能产生一次主 AI 请求',
      );
      expect(
        aliceEvents.where(
          (event) => event.type == MultiplayerEventType.aiRequest,
        ),
        isEmpty,
        reason: 'AI 请求只发送给指定 Host',
      );

      final rawBundle = (resolution.payload['roundActionBundle'] as Map)
          .cast<String, Object?>();
      expect(rawBundle['turnId'], turn.turnId);
      final actions = (rawBundle['actions'] as List)
          .cast<Map>()
          .map((value) => value.cast<String, Object?>())
          .toList();
      expect(actions, hasLength(2));
      expect(actions[0]['playerId'], alice.credentials!.playerId);
      expect(actions[0]['characterId'], 'alice-character');
      expect(actions[0]['content'], '我进入左侧走廊并观察墙面。');
      expect(actions[1]['playerId'], bob.credentials!.playerId);
      expect(actions[1]['characterId'], 'bob-character');
      expect(actions[1]['content'], '我去右侧诊室检查。');

      final continuationFuture = bob.events.firstWhere(
        (event) =>
            event.type == MultiplayerEventType.aiRequest &&
            event.payload['requestId'] != resolution.payload['requestId'],
      );
      await bob.sendAIResponse(
        requestId: resolution.payload['requestId'] as String,
        response: OpenAIChatResponse(
          content: '',
          toolCalls: [
            OpenAIToolCall(
              id: 'move-alice-left',
              name: 'move_character',
              arguments: {
                'actorPlayerId': alice.credentials!.playerId,
                'actorCharacterId': 'alice-character',
                'characterId': 'alice-character',
                'targetLocationId': 'left_corridor',
                'turnId': turn.turnId,
                'actionId': aliceActionId,
                'reason': '亚瑟进入左侧走廊',
              },
            ),
            OpenAIToolCall(
              id: 'move-bob-right',
              name: 'move_character',
              arguments: {
                'actorPlayerId': bob.credentials!.playerId,
                'actorCharacterId': 'bob-character',
                'characterId': 'bob-character',
                'targetLocationId': 'right_clinic',
                'turnId': turn.turnId,
                'actionId': bobActionId,
                'reason': '莉娜进入右侧诊室',
              },
            ),
          ],
        ).toJson(),
      );
      final continuation = await continuationFuture;
      await bob.sendAIResponse(
        requestId: continuation.payload['requestId'] as String,
        response: const OpenAIChatResponse(
          content: '亚瑟进入左侧走廊；与此同时，莉娜推开了右侧诊室的门。',
          toolCalls: [],
        ).toJson(),
      );
      await _waitUntil(
        () =>
            alice.snapshot!.room.currentTurn!.turnId != turn.turnId &&
            alice.snapshot!.room.currentTurn!.phase ==
                MultiplayerTurnPhase.collecting,
      );

      final authoritative = server.inspectRoom(
        alice.credentials!.roomId,
        includeSecrets: true,
      );
      final aliceCharacter = authoritative.session!.playerCharacters
          .singleWhere((character) => character.id == 'alice-character');
      final bobCharacter = authoritative.session!.playerCharacters.singleWhere(
        (character) => character.id == 'bob-character',
      );
      expect(aliceCharacter.locationId, 'left_corridor');
      expect(bobCharacter.locationId, 'right_clinic');
      final roundEvents = authoritative.session!.eventLog.where(
        (event) =>
            event.type == TRPGEventType.playerAction &&
            event.payload['turnId'] == turn.turnId,
      );
      expect(roundEvents, hasLength(2));
      expect(roundEvents.map((event) => event.payload['characterId']).toSet(), {
        'alice-character',
        'bob-character',
      });

      final reconnectTurn = alice.snapshot!.room.currentTurn!;
      await alice.confirmTurnAction(
        turnId: reconnectTurn.turnId,
        content: '我留在左侧走廊。',
        actionId: 'reconnect-action',
      );
      final savedCredentials = alice.credentials!;
      await alice.transport.disconnect();
      await alice.reconnect(savedCredentials);
      await _waitUntil(
        () =>
            alice.snapshot?.room.currentTurn?.turnId == reconnectTurn.turnId &&
            alice
                    .snapshot!
                    .room
                    .currentTurn!
                    .playerActions[savedCredentials.playerId]
                    ?.confirmed ==
                true,
      );
      expect(
        alice
            .snapshot!
            .room
            .currentTurn!
            .playerActions[savedCredentials.playerId]!
            .content,
        '我留在左侧走廊。',
      );
    },
    timeout: const Timeout(Duration(seconds: 35)),
  );

  test('turn model round trip redacts other player action content', () {
    final now = DateTime(2026, 8, 15);
    final turn = MultiplayerTurn(
      turnId: 'turn-1',
      roundNumber: 7,
      startedAt: now,
      expectedPlayerIds: const ['a', 'b'],
      confirmedPlayerIds: const ['a'],
      playerActions: {
        'a': PlayerTurnAction(
          actionId: 'action-a',
          turnId: 'turn-1',
          playerId: 'a',
          playerDisplayName: 'Alice',
          characterId: 'char-a',
          characterName: '亚瑟',
          content: '向左',
          confirmed: true,
          isPass: false,
          submittedAt: now,
        ),
      },
    );

    final roundTrip = MultiplayerTurn.fromJson(turn.toJson());
    expect(roundTrip.playerActions['a']!.content, '向左');
    expect(roundTrip.forViewer('b').playerActions['a']!.content, isEmpty);
    expect(roundTrip.forViewer('a').playerActions['a']!.content, '向左');
    expect(
      roundTrip.forViewer(null, isGm: true).playerActions['a']!.content,
      '向左',
    );
  });

  test('human GM collects all actions without selecting a character', () async {
    final data = await Directory.systemTemp.createTemp('human-gm-turn-');
    final server = MultiplayerAuthoritativeServer(
      config: MultiplayerServerConfig(
        address: '127.0.0.1',
        port: 0,
        persistenceDirectory: data.path,
        settlementGrace: const Duration(milliseconds: 80),
      ),
    );
    await server.start();
    final endpoint = 'ws://127.0.0.1:${server.port}/ws';
    final gm = MultiplayerClient();
    final player = MultiplayerClient();
    final gmEvents = <MultiplayerEnvelope>[];
    gm.events.listen(gmEvents.add);
    addTearDown(() async {
      await gm.close();
      await player.close();
      await server.stop();
      await data.delete(recursive: true);
    });

    final createdFuture = gm.states.first;
    await gm.createRoom(
      endpoint: endpoint,
      roomName: '人类主持测试',
      playerName: '主持人',
      gmMode: AIHostMode.humanGm,
    );
    final created = await createdFuture;
    expect(created.room.players.single.role, TRPGPlayerRole.humanGm);
    expect(created.room.players.single.characterId, isNull);
    final joinedFuture = player.states.first;
    await player.joinRoom(
      endpoint: endpoint,
      roomCode: created.room.roomCode,
      playerName: '调查员',
    );
    await joinedFuture;
    await player.selectCharacter(
      _character(player.credentials!.playerId, 'investigator', '调查员角色'),
    );
    await player.setReady(true);
    await _waitUntil(
      () =>
          gm.snapshot?.room.players.any(
            (value) =>
                value.playerId == player.credentials!.playerId &&
                value.isReady &&
                value.characterId != null,
          ) ==
          true,
    );

    await gm.startGame();
    await _waitUntil(
      () =>
          player.snapshot?.room.currentTurn?.phase ==
          MultiplayerTurnPhase.collecting,
    );
    final turn = player.snapshot!.room.currentTurn!;
    expect(turn.expectedPlayerIds, [player.credentials!.playerId]);
    await player.confirmTurnAction(
      turnId: turn.turnId,
      content: '我检查房门。',
      actionId: 'human-gm-action',
    );
    await _waitUntil(
      () =>
          gm.snapshot?.room.currentTurn?.phase ==
          MultiplayerTurnPhase.gmResponding,
    );
    expect(
      gm
          .snapshot!
          .room
          .currentTurn!
          .playerActions[player.credentials!.playerId]!
          .content,
      '我检查房门。',
    );
    expect(
      gmEvents.where((event) => event.type == MultiplayerEventType.aiRequest),
      isEmpty,
    );
    await gm.resolveHumanGmTurn(turn.turnId, '房门后传来轻微的脚步声。');
    await _waitUntil(
      () => gm.snapshot!.room.currentTurn!.turnId != turn.turnId,
    );
    expect(gm.snapshot!.session!.chatHistory.last.content, '房门后传来轻微的脚步声。');
  });
}

PlayerCharacter _character(String playerId, String characterId, String name) =>
    PlayerCharacter(
      id: characterId,
      playerId: playerId,
      name: name,
      stats: const {'STR': 10, 'DEX': 12, 'INT': 12, 'PER': 14, 'CHA': 10},
      metadata: const {'locationId': 'main_hall'},
    );

Future<void> _waitUntil(
  bool Function() test, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (test()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('condition not met', timeout);
}
