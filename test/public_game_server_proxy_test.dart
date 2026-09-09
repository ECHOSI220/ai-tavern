import 'dart:convert';

import 'package:ai_tavern/services/trpg/public_game_server_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('keeps an Edge Function prefix when creating a public room', () async {
    final api = PublicGameServerApi(
      client: MockClient((request) async {
        expect(request.url.host, 'project.supabase.co');
        expect(request.url.path, '/functions/v1/game-server-proxy/v1/rooms');
        expect(request.headers['Authorization'], 'Bearer access-token');
        return http.Response(
          jsonEncode({
            'roomId': 'room-id',
            'roomCode': 'ABC123',
            'playerId': 'player-id',
            'playerSessionId': 'player-session-id',
            'reconnectToken': 'reconnect-token',
            'revision': 1,
            'socketUrl':
                'wss://project.supabase.co/functions/v1/'
                'game-server-proxy/v1/rooms/room-id/socket',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.createRoom(
      endpoint: 'https://project.supabase.co/functions/v1/game-server-proxy',
      accessToken: 'access-token',
      roomName: 'Test room',
      playerName: 'Tester',
      campaignId: 'campaign-id',
      maxPlayers: 4,
      allowPlayerPrivateChat: true,
    );

    expect(result.credentials.roomId, 'room-id');
    expect(result.socketUrl, contains('/game-server-proxy/v1/rooms/'));
    api.close();
  });
}
