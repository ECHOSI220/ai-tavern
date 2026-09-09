import 'dart:async';
import 'dart:io';

import 'package:ai_tavern/models/multiplayer_models.dart';
import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/models/trpg_presentation_models.dart';
import 'package:ai_tavern/services/ai/openai_compatible_provider.dart';
import 'package:ai_tavern/services/trpg/multiplayer_server.dart';
import 'package:ai_tavern/services/trpg/multiplayer_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  test(
    'two real WebSocket clients share authoritative tools and reconnect',
    () async {
      final data = await Directory.systemTemp.createTemp('ai-tavern-multi-');
      final server = MultiplayerAuthoritativeServer(
        config: MultiplayerServerConfig(
          address: '127.0.0.1',
          port: 0,
          persistenceDirectory: data.path,
          aiRequestTimeout: const Duration(seconds: 5),
          settlementGrace: const Duration(milliseconds: 80),
          offlineGrace: const Duration(milliseconds: 250),
        ),
      );
      await server.start();
      final endpoint = 'ws://127.0.0.1:${server.port}/ws';
      final a = MultiplayerClient();
      final b = MultiplayerClient();
      addTearDown(() async {
        await a.close();
        await b.close();
        await server.stop();
        await data.delete(recursive: true);
      });

      final aCreated = a.states.first;
      await a.createRoom(
        endpoint: endpoint,
        roomName: '雾港双人团',
        playerName: 'Alice',
      );
      final created = await aCreated;
      expect(created.room.roomCode, hasLength(6));

      final bJoined = b.states.first;
      await b.joinRoom(
        endpoint: endpoint,
        roomCode: created.room.roomCode,
        playerName: 'Bob',
      );
      await bJoined;
      await _waitUntil(() => a.snapshot?.room.players.length == 2);

      await a.selectCharacter(_character(a.credentials!.playerId, 'Alice角色'));
      await b.selectCharacter(_character(b.credentials!.playerId, 'Bob角色'));
      await a.setReady(true);
      await b.setReady(true);
      await _waitUntil(
        () => a.snapshot!.room.players.every(
          (player) => player.isReady && player.characterId != null,
        ),
      );

      final hostRequested = b.events.firstWhere(
        (event) => event.type == MultiplayerEventType.hostRequested,
      );
      await a.requestHost(b.credentials!.playerId, modelId: 'test-tool-model');
      await hostRequested;
      await b.acceptHost(modelId: 'test-tool-model');
      await _waitUntil(
        () => a.snapshot!.room.aiHostConfig.status == AIHostStatus.ready,
      );

      final openingRequest = b.events.firstWhere(
        (event) => event.type == MultiplayerEventType.aiRequest,
      );
      await a.startGame();
      final opening = await openingRequest;
      await b.sendAIResponse(
        requestId: opening.payload['requestId'] as String,
        response: OpenAIChatResponse(
          content: '浓雾笼罩旧港，两名调查者在封锁线前会合。',
          toolCalls: [],
        ).toJson(),
      );
      await _waitUntil(
        () =>
            a.snapshot?.session?.chatHistory.isNotEmpty == true &&
            a.snapshot!.session!.chatHistory.last.content.contains('两名调查者') ==
                true &&
            a.snapshot!.room.currentTurn?.phase ==
                MultiplayerTurnPhase.collecting,
      );

      final firstAIRequest = b.events.firstWhere(
        (event) => event.type == MultiplayerEventType.aiRequest,
      );
      final firstTurnId = a.snapshot!.room.currentTurn!.turnId;
      await a.submitAction('我检查仓库门旁的脚印。', actionId: 'action-check');
      await b.confirmTurnAction(turnId: firstTurnId, content: '');
      final request = await firstAIRequest;
      final skillCall = OpenAIToolCall(
        id: 'authoritative-check-1',
        name: 'skill_check',
        arguments: {
          'characterId': 'alice-character',
          'skillId': 'perception',
          'difficulty': 10,
          'reason': '检查脚印',
          'actorPlayerId': a.credentials!.playerId,
          'actorCharacterId': 'alice-character',
          'turnId': firstTurnId,
          'actionId': 'action-check',
        },
      );
      final toolResult = a.events.firstWhere(
        (event) =>
            event.type == MultiplayerEventType.toolResult &&
            event.payload['toolCallId'] == skillCall.id,
      );
      final secondAIRequest = b.events.firstWhere(
        (event) =>
            event.type == MultiplayerEventType.aiRequest &&
            event.payload['requestId'] != request.payload['requestId'],
      );
      await b.sendAIResponse(
        requestId: request.payload['requestId'] as String,
        response: OpenAIChatResponse(
          content: '',
          toolCalls: [skillCall],
        ).toJson(),
      );
      final result = await toolResult;
      expect(result.payload['success'], isTrue);
      final continuation = await secondAIRequest;
      await b.sendAIResponse(
        requestId: continuation.payload['requestId'] as String,
        response: const OpenAIChatResponse(
          content: '程序检定完成后，你确认脚印通向侧门。',
          toolCalls: [],
        ).toJson(),
      );
      await _waitUntil(
        () => a.snapshot!.session!.eventLog.any(
          (event) => event.type == TRPGEventType.skillCheck,
        ),
      );
      // The skill-check event and the following GM narration are broadcast as
      // two authoritative snapshots.  Wait for both clients to receive the
      // latter before comparing the complete session document.
      await _waitUntil(
        () =>
            a.snapshot!.session!.updatedAt == b.snapshot!.session!.updatedAt &&
            a.snapshot!.session!.chatHistory.length ==
                b.snapshot!.session!.chatHistory.length,
      );
      expect(
        b.snapshot!.session!.ruleState.diceHistory.single.rolls.single,
        inInclusiveRange(1, 20),
      );
      expect(
        a.snapshot!.session!.toJson(),
        equals(b.snapshot!.session!.toJson()),
      );

      // Presentation is server ordered and state is restored through snapshot.
      final presentation = PresentationEvent(
        eventId: 'scene-sync-1',
        type: PresentationEventType.sceneBackground,
        sequenceNumber: 1,
        createdAt: DateTime.now(),
        payload: const {'backgroundId': 'warehouse'},
      );
      await a.sendPresentationEvent({
        ...presentation.toJson(),
        'state': const CurrentPresentationState(
          backgroundId: 'warehouse',
          bgmId: 'mystery',
          ambientId: 'rain',
          sequenceNumber: 1,
        ).toJson(),
      });
      await _waitUntil(
        () =>
            b.snapshot?.session?.presentationState.backgroundId == 'warehouse',
      );
      expect(b.snapshot!.session!.presentationState.bgmId, 'mystery');
      expect(b.snapshot!.session!.presentationState.ambientId, 'rain');

      // Replay the same network command: the server must not roll or mutate twice.
      final beforeReplay = server
          .inspectRoom(a.credentials!.roomId, includeSecrets: true)
          .session!;
      final originalSkill = beforeReplay.toolExecutions.singleWhere(
        (record) => record.toolCallId == skillCall.id,
      );
      await b.sendAIResponse(
        requestId: continuation.payload['requestId'] as String,
        response: OpenAIChatResponse(
          content: '',
          toolCalls: [skillCall],
        ).toJson(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final afterReplay = server
          .inspectRoom(a.credentials!.roomId, includeSecrets: true)
          .session!;
      expect(
        afterReplay.toolExecutions.where(
          (record) => record.toolCallId == skillCall.id,
        ),
        hasLength(1),
      );
      expect(
        afterReplay.toolExecutions
            .singleWhere((record) => record.toolCallId == skillCall.id)
            .result,
        originalSkill.result,
      );
      expect(afterReplay.ruleState.diceHistory, hasLength(1));

      // Public client snapshots strip hidden GM fields.
      expect(a.snapshot!.session!.gmState.privateNotes, isEmpty);
      expect(
        server
            .inspectRoom(a.credentials!.roomId, includeSecrets: true)
            .session!
            .gmState
            .privateNotes,
        isNotEmpty,
      );

      final bCredentials = b.credentials!;
      await b.transport.disconnect();
      await _waitUntil(
        () =>
            a.snapshot!.room.aiHostConfig.status == AIHostStatus.offline &&
            a.snapshot!.room.status == MultiplayerRoomStatus.paused,
      );
      final unchangedSessionId = a.snapshot!.session!.id;
      await a.requestHost(
        a.credentials!.playerId,
        modelId: 'replacement-tool-model',
      );
      await a.acceptHost(modelId: 'replacement-tool-model');
      await _waitUntil(
        () =>
            a.snapshot!.room.aiHostConfig.providerPlayerId ==
                a.credentials!.playerId &&
            a.snapshot!.room.status == MultiplayerRoomStatus.playing,
      );
      expect(a.snapshot!.session!.id, unchangedSessionId);
      await a.skipTurnPlayer(
        a.snapshot!.room.currentTurn!.turnId,
        b.credentials!.playerId,
      );
      final transferredRequest = a.events.firstWhere(
        (event) => event.type == MultiplayerEventType.aiRequest,
      );
      await a.submitAction('更换主持后继续前往仓库。');
      final transferred = await transferredRequest;
      await a.sendAIResponse(
        requestId: transferred.payload['requestId'] as String,
        response: const OpenAIChatResponse(
          content: '主持模型已经切换，但雾港的时间线与调查进度保持不变。',
          toolCalls: [],
        ).toJson(),
      );
      await _waitUntil(
        () =>
            a.snapshot!.session!.chatHistory.last.content.contains('时间线') ==
            true,
      );
      await b.reconnect(bCredentials);
      await _waitUntil(
        () =>
            b.snapshot!.room.aiHostConfig.status == AIHostStatus.ready &&
            b.snapshot!.room.revision == a.snapshot!.room.revision,
      );
      expect(b.snapshot!.session!.chatHistory, isNotEmpty);
      expect(b.snapshot!.session!.playerCharacters.first.hp, 20);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('server restart restores a paused room and reconnect token', () async {
    final data = await Directory.systemTemp.createTemp('ai-tavern-restore-');
    var server = MultiplayerAuthoritativeServer(
      config: MultiplayerServerConfig(
        address: '127.0.0.1',
        port: 0,
        persistenceDirectory: data.path,
      ),
    );
    await server.start();
    final client = MultiplayerClient();
    final createdFuture = client.states.first;
    await client.createRoom(
      endpoint: 'ws://127.0.0.1:${server.port}/ws',
      roomName: '可恢复房间',
      playerName: 'Owner',
    );
    await createdFuture;
    final credentials = client.credentials!;
    await client.transport.disconnect();
    await server.stop();

    server = MultiplayerAuthoritativeServer(
      config: MultiplayerServerConfig(
        address: '127.0.0.1',
        port: 0,
        persistenceDirectory: data.path,
      ),
    );
    await server.start();
    final restored = MultiplayerClient();
    final snapshotFuture = restored.states.first;
    await restored.reconnect(
      MultiplayerCredentials(
        endpoint: 'ws://127.0.0.1:${server.port}/ws',
        roomId: credentials.roomId,
        playerId: credentials.playerId,
        sessionToken: credentials.sessionToken,
      ),
    );
    final snapshot = await snapshotFuture;
    expect(snapshot.room.roomName, '可恢复房间');
    expect(snapshot.room.players.single.playerId, credentials.playerId);

    await restored.close();
    await client.close();
    await server.stop();
    await data.delete(recursive: true);
  });

  test(
    'secret action, private roll and private message never reach another player',
    () async {
      final data = await Directory.systemTemp.createTemp('ai-tavern-secret-');
      final server = MultiplayerAuthoritativeServer(
        config: MultiplayerServerConfig(
          address: '127.0.0.1',
          port: 0,
          persistenceDirectory: data.path,
        ),
      );
      await server.start();
      final endpoint = 'ws://127.0.0.1:${server.port}/ws';
      final a = MultiplayerClient();
      final b = MultiplayerClient();
      final aEvents = <MultiplayerEnvelope>[];
      final bEvents = <MultiplayerEnvelope>[];
      a.events.listen(aEvents.add);
      b.events.listen(bEvents.add);
      addTearDown(() async {
        await a.close();
        await b.close();
        await server.stop();
        await data.delete(recursive: true);
      });

      final createdFuture = a.states.first;
      await a.createRoom(
        endpoint: endpoint,
        roomName: '秘密测试',
        playerName: 'Alice',
      );
      final created = await createdFuture;
      final joinedFuture = b.states.first;
      await b.joinRoom(
        endpoint: endpoint,
        roomCode: created.room.roomCode,
        playerName: 'Bob',
      );
      await joinedFuture;
      await _waitUntil(() => a.snapshot?.room.players.length == 2);
      await a.selectCharacter(_character(a.credentials!.playerId, 'Alice角色'));
      await b.selectCharacter(_character(b.credentials!.playerId, 'Bob角色'));
      await a.setReady(true);
      await b.setReady(true);
      await a.requestHost(a.credentials!.playerId, modelId: 'host');
      await _waitUntil(
        () => a.snapshot?.room.aiHostConfig.status == AIHostStatus.pending,
      );
      await a.acceptHost(modelId: 'host');
      await _waitUntil(
        () => a.snapshot?.room.aiHostConfig.status == AIHostStatus.ready,
      );
      final openingFuture = a.events.firstWhere(
        (event) => event.type == MultiplayerEventType.aiRequest,
      );
      await a.startGame();
      final opening = await openingFuture;
      await a.sendAIResponse(
        requestId: opening.payload['requestId'] as String,
        response: const OpenAIChatResponse(
          content: '公开开场',
          toolCalls: [],
        ).toJson(),
      );
      await _waitUntil(() => b.snapshot?.session != null);
      aEvents.clear();
      bEvents.clear();

      final secretRequestFuture = a.events.firstWhere(
        (event) => event.type == MultiplayerEventType.aiRequest,
      );
      await a.submitSecretAction('我偷偷检查桌子抽屉。', actionId: 'secret-a');
      final secretRequest = await secretRequestFuture;
      await a.sendAIResponse(
        requestId: secretRequest.payload['requestId'] as String,
        response: const OpenAIChatResponse(
          content: '你发现了一封私信。',
          toolCalls: [],
        ).toJson(),
      );
      await _waitUntil(
        () => a.snapshot!.session!.immersionState.timeline.any(
          (entry) => entry.detail.contains('私信'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        bEvents.where(
          (event) =>
              event.type == MultiplayerEventType.secretAction ||
              (event.type == MultiplayerEventType.gmMessage &&
                  event.payload['content'] == '你发现了一封私信。'),
        ),
        isEmpty,
      );
      expect(
        b.snapshot!.session!.immersionState.timeline.any(
          (entry) => entry.detail.contains('私信'),
        ),
        isFalse,
      );

      aEvents.clear();
      bEvents.clear();
      await a.privateRoll(reason: '秘密感知');
      await _waitUntil(
        () => aEvents.any(
          (event) => event.type == MultiplayerEventType.privateRoll,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        bEvents.where(
          (event) => event.type == MultiplayerEventType.privateRoll,
        ),
        isEmpty,
      );

      await a.sendPrivateMessage(
        '只给 Alice 自己的备忘',
        recipientPlayerIds: [a.credentials!.playerId],
      );
      await _waitUntil(
        () => a.snapshot!.session!.immersionState.privateMessages.isNotEmpty,
      );
      expect(b.snapshot!.session!.immersionState.privateMessages, isEmpty);

      final full = server
          .inspectRoom(a.credentials!.roomId, includeSecrets: true)
          .session!;
      expect(
        full.immersionState.timeline.any(
          (entry) => entry.detail.contains('私信'),
        ),
        isTrue,
      );

      // Reconnect keeps per-player authorization: Bob still cannot download
      // Alice's secret state, while the server retains it for host transfer.
      final bCredentials = b.credentials!;
      await b.transport.disconnect();
      await b.reconnect(bCredentials);
      await _waitUntil(
        () =>
            b.snapshot?.room.players.any(
              (player) =>
                  player.playerId == bCredentials.playerId &&
                  player.connectionStatus == TRPGConnectionStatus.online,
            ) ==
            true,
      );
      expect(
        b.snapshot!.session!.immersionState.timeline.any(
          (entry) => entry.detail.contains('私信'),
        ),
        isFalse,
      );
      await a.requestHost(b.credentials!.playerId, modelId: 'replacement');
      await b.acceptHost(modelId: 'replacement');
      await _waitUntil(
        () =>
            a.snapshot!.room.aiHostConfig.providerPlayerId ==
            b.credentials!.playerId,
      );
      expect(
        server
            .inspectRoom(a.credentials!.roomId, includeSecrets: true)
            .session!
            .immersionState
            .timeline
            .any((entry) => entry.detail.contains('私信')),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

PlayerCharacter _character(String playerId, String name) => PlayerCharacter(
  id: name.startsWith('Alice') ? 'alice-character' : const Uuid().v4(),
  playerId: playerId,
  name: name,
  stats: const {'STR': 10, 'DEX': 12, 'INT': 12, 'PER': 14, 'CHA': 10},
  skills: const {'perception': 2},
);

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
