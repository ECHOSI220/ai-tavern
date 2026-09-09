import 'dart:async';
import 'package:ai_tavern/models/api_profile.dart';
import 'package:ai_tavern/models/multiplayer_models.dart';
import 'package:ai_tavern/repositories/api_repository.dart';
import 'package:ai_tavern/services/ai_service.dart';
import 'package:ai_tavern/services/ai/ai_provider.dart';
import 'package:ai_tavern/services/secure_storage_service.dart';
import 'package:ai_tavern/services/storage_service.dart';
import 'package:ai_tavern/services/trpg/client_ai_host_service.dart';
import 'package:ai_tavern/services/trpg/multiplayer_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client extends MultiplayerClient {
  final incoming = StreamController<MultiplayerEnvelope>.broadcast();
  final responses = <Map<String, Object?>>[];
  @override
  Stream<MultiplayerEnvelope> get events => incoming.stream;
  @override
  Future<void> command(
    MultiplayerEventType type, [
    Map<String, Object?> payload = const {},
  ]) async {
    responses.add(payload);
  }

  @override
  Future<void> sendAIResponse({
    required String requestId,
    required Map<String, Object?> response,
    int inputTokens = 0,
    int outputTokens = 0,
  }) async {
    responses.add({'requestId': requestId, 'response': response});
  }
}

class _Repository extends ApiRepository {
  _Repository() : super(StorageService(), SecureStorageService());
  @override
  Future<String> readApiKey(String id) async => 'fake-key';
}

class _AI extends AiService {
  final pending = <Completer<ToolChatResponse>>[];
  @override
  Future<ToolChatResponse> completeWithTools({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
  }) {
    expect(profile.timeoutSeconds, inInclusiveRange(15, 120));
    final result = Completer<ToolChatResponse>();
    pending.add(result);
    return result.future;
  }
}

void main() {
  test(
    'duplicate request is ignored and a retried request suppresses the late old response',
    () async {
      final client = _Client(), ai = _AI();
      final service = ClientAIHostService(
        client: client,
        apiRepository: _Repository(),
        aiService: ai,
      );
      await service.activate(
        const ApiProfile(
          id: 'test',
          name: 'test',
          baseUrl: 'https://example.invalid',
          model: 'fake',
          timeoutSeconds: 0,
        ),
      );
      void emit(String id) => client.incoming.add(
        MultiplayerEnvelope(
          type: MultiplayerEventType.aiRequest,
          roomId: 'test',
          payload: {'requestId': id},
        ),
      );
      Future<void> flush() => Future<void>.delayed(Duration.zero);
      emit('old');
      await flush();
      emit('old');
      await flush();
      expect(ai.pending, hasLength(1));
      emit('new');
      await flush();
      expect(ai.pending, hasLength(2));
      ai.pending[0].complete(
        ToolChatResponse.fromJson({
          'choices': [
            {
              'message': {'content': 'old'},
            },
          ],
        }),
      );
      await flush();
      expect(client.responses, isEmpty);
      ai.pending[1].complete(
        ToolChatResponse.fromJson({
          'choices': [
            {
              'message': {'content': 'new'},
            },
          ],
        }),
      );
      await flush();
      expect(client.responses.single['requestId'], 'new');
      emit('new');
      await flush();
      expect(ai.pending, hasLength(2));
      await service.dispose();
      await client.incoming.close();
    },
  );
  test('provider failures relay a safe code, never raw credentials', () async {
    final client = _Client(), ai = _AI();
    final service = ClientAIHostService(
      client: client,
      apiRepository: _Repository(),
      aiService: ai,
    );
    await service.activate(
      const ApiProfile(
        id: 'test',
        name: 'test',
        baseUrl: 'https://example.invalid',
        model: 'fake',
      ),
    );
    client.incoming.add(
      MultiplayerEnvelope(
        type: MultiplayerEventType.aiRequest,
        roomId: 'test',
        payload: {'requestId': 'failed'},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    ai.pending.single.completeError(
      const AiException('private-key-here', code: 'AI_TIMEOUT'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(client.responses.single, {
      'requestId': 'failed',
      'error': 'AI_TIMEOUT',
    });
    await service.dispose();
    await client.incoming.close();
  });
}
