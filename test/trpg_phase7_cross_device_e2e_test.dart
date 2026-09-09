import 'dart:convert';
import 'dart:io';

import 'package:ai_tavern/models/social_models.dart';
import 'package:ai_tavern/services/trpg/multiplayer_server.dart';
import 'package:ai_tavern/services/trpg/multiplayer_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'one account continues the same permanent campaign on a second device',
    () async {
      final data = await Directory.systemTemp.createTemp('tavern_phase7_e2e_');
      final server = MultiplayerAuthoritativeServer(
        config: MultiplayerServerConfig(
          address: '127.0.0.1',
          port: 0,
          persistenceDirectory: data.path,
          offlineGrace: const Duration(milliseconds: 100),
        ),
      );
      await server.start();
      final httpBase = 'http://127.0.0.1:${server.port}';
      final ws = 'ws://127.0.0.1:${server.port}/ws';
      final client = http.Client();
      final pc = MultiplayerClient();
      final phone = MultiplayerClient();
      addTearDown(() async {
        client.close();
        await pc.close();
        await phone.close();
        await server.stop();
        await data.delete(recursive: true);
      });

      final first = AuthTokens.fromJson(
        await _post(client, '$httpBase/api/auth/register', {
          'handle': 'cross_device_user',
          'displayName': '跨设备玩家',
          'password': 'cross-device-pass',
          'deviceName': 'Windows PC',
          'platform': 'windows',
        }),
      );
      final campaign = PersistentCampaignRoom.fromJson(
        await _post(client, '$httpBase/api/campaigns', {
          'campaignId': 'mist_harbor_test',
          'title': '雾港跨设备团',
        }, token: first.accessToken),
      );

      final pcState = pc.states.first;
      await pc.createRoom(
        endpoint: ws,
        roomName: campaign.title,
        playerName: first.account.displayName,
        account: first,
        kind: CampaignRoomKind.persistent,
        persistentCampaignRoomId: campaign.id,
      );
      final created = await pcState;
      final originalRoomId = created.room.roomId;
      final originalPlayerId = pc.credentials!.playerId;

      final second = AuthTokens.fromJson(
        await _post(client, '$httpBase/api/auth/login', {
          'handle': 'cross_device_user',
          'password': 'cross-device-pass',
          'deviceName': 'Android Phone',
          'platform': 'android',
        }),
      );
      final phoneState = phone.states.first;
      await phone.createRoom(
        endpoint: ws,
        roomName: campaign.title,
        playerName: second.account.displayName,
        account: second,
        kind: CampaignRoomKind.persistent,
        persistentCampaignRoomId: campaign.id,
      );
      final resumed = await phoneState;
      expect(resumed.room.roomId, originalRoomId);
      expect(phone.credentials!.playerId, originalPlayerId);
      expect(resumed.room.players, hasLength(1));
      expect(resumed.room.ownerUserId, first.account.userId);

      final campaigns = await _get(
        client,
        '$httpBase/api/campaigns',
        token: second.accessToken,
      );
      expect((campaigns['campaigns'] as List).single['id'], campaign.id);
      final devices = await _get(
        client,
        '$httpBase/api/devices',
        token: second.accessToken,
      );
      expect(devices['devices'], hasLength(2));
    },
  );
}

Future<Map<String, Object?>> _post(
  http.Client client,
  String url,
  Map<String, Object?> body, {
  String? token,
}) async {
  final response = await client.post(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
    body: jsonEncode(body),
  );
  expect(
    response.statusCode,
    inInclusiveRange(200, 299),
    reason: response.body,
  );
  return (jsonDecode(response.body) as Map).cast<String, Object?>();
}

Future<Map<String, Object?>> _get(
  http.Client client,
  String url, {
  required String token,
}) async {
  final response = await client.get(
    Uri.parse(url),
    headers: {'Authorization': 'Bearer $token'},
  );
  expect(response.statusCode, HttpStatus.ok, reason: response.body);
  return (jsonDecode(response.body) as Map).cast<String, Object?>();
}
