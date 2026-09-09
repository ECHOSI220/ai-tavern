import 'dart:convert';

import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/models/social_models.dart';
import 'package:ai_tavern/repositories/api_repository.dart';
import 'package:ai_tavern/repositories/trpg_session_repository.dart';
import 'package:ai_tavern/services/secure_storage_service.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:ai_tavern/services/trpg/account_client_service.dart';
import 'package:ai_tavern/services/trpg/cloud_save_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

TRPGSession session({TRPGMode mode = TRPGMode.solo}) => TRPGSession(
  id: 'cloud-test-save',
  title: '旧旅店',
  mode: mode,
  campaignId: 'inn',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  lastPlayedAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('solo cloud save round trips with the same identity and schema', () {
    final original = session();
    final restored = CloudSaveService.decode(CloudSaveService.encode(original));
    expect(restored.toJson(), original.toJson());
  });
  test('player-filtered multiplayer state is not a canonical cloud save', () {
    expect(
      () => CloudSaveService.encode(session(mode: TRPGMode.multiplayer)),
      throwsStateError,
    );
  });
  test('future save schema is rejected without silently dropping fields', () {
    final body = CloudSaveService.encode(session());
    final state = body['state'] as Map;
    (state['session'] as Map)['schemaVersion'] = 999;
    expect(() => CloudSaveService.decode(body), throwsStateError);
  });
  test(
    'signed-in cloud saves use Supabase REST without a Worker round trip',
    () async {
      final requests = <http.Request>[];
      final storage = StorageService();
      final account =
          AccountClientService(
              apiRepository: ApiRepository(storage, SecureStorageService()),
              client: MockClient((request) async {
                requests.add(request);
                expect(request.url.host, 'project.supabase.co');
                expect(request.url.path, '/rest/v1/campaigns');
                expect(request.headers['apikey'], 'anon-key');
                expect(request.headers['Authorization'], 'Bearer access-token');
                if (request.method == 'POST') {
                  final body = (jsonDecode(request.body) as Map)
                      .cast<String, Object?>();
                  expect(body['owner_id'], 'user-id');
                  expect(body['state'], isA<Map>());
                  return http.Response(
                    '[{"id":"cloud-id","title":"旧旅店"}]',
                    201,
                    headers: {'content-type': 'application/json'},
                  );
                }
                return http.Response(
                  '[{"id":"cloud-id","title":"旧旅店"}]',
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }),
            )
            ..supabaseUrl = 'https://project.supabase.co'
            ..supabaseAnonKey = 'anon-key'
            ..tokens = AuthTokens(
              accessToken: 'access-token',
              refreshToken: 'refresh-token',
              expiresAt: DateTime.utc(2027),
              deviceSessionId: 'device-id',
              account: UserAccount(
                userId: 'user-id',
                handle: 'user@example.com',
                displayName: 'User',
                createdAt: DateTime.utc(2026),
                lastOnlineAt: DateTime.utc(2026),
              ),
            );
      final service = CloudSaveService(
        account: account,
        repository: TRPGSessionRepository(storage),
      );

      await service.upload(session());
      final saves = await service.list();

      expect(requests.map((request) => request.method), ['POST', 'GET']);
      expect(saves.single['id'], 'cloud-id');
      account.dispose();
    },
  );
  test(
    'cloud restore cannot overwrite an existing or damaged local row',
    () async {
      final storage = StorageService();
      await storage.initialize(databasePath: ':memory:');
      addTearDown(storage.close);
      final repository = TRPGSessionRepository(storage);
      final original = session();
      await repository.upsert(original, onlyIfAbsent: true);
      await expectLater(
        repository.upsert(
          TRPGSession.fromJson({...original.toJson(), 'title': '覆盖内容'}),
          onlyIfAbsent: true,
        ),
        throwsStateError,
      );
      expect((await repository.getById(original.id))!.title, '旧旅店');
      await storage.database.update(
        'trpg_sessions',
        {'payload': 'damaged'},
        where: 'id = ?',
        whereArgs: [original.id],
      );
      await expectLater(
        repository.upsert(original, onlyIfAbsent: true),
        throwsStateError,
      );
      expect(
        (await storage.database.query('trpg_sessions')).single['payload'],
        'damaged',
      );
    },
  );
}
