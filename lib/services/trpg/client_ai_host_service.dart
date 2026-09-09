// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';

import '../../models/api_profile.dart';
import '../../models/multiplayer_models.dart';
import '../ai_service.dart';
import '../../repositories/api_repository.dart';
import 'multiplayer_transport.dart';

class ClientAIHostService {
  ClientAIHostService({
    required this.client,
    required this.apiRepository,
    required this.aiService,
  });
  final MultiplayerClient client;
  final ApiRepository apiRepository;
  final AiService aiService;
  ApiProfile? _profile;
  StreamSubscription<MultiplayerEnvelope>? _subscription;
  Timer? _heartbeat;
  int requests = 0, errors = 0;

  Future<void> activate(ApiProfile profile) async {
    _profile = profile;
    await _subscription?.cancel();
    _subscription = client.events.listen(_handleEvent);
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      client.heartbeat().catchError((_) {});
    });
  }

  Future<bool> testToolCalling(ApiProfile profile) async {
    final apiKey = await apiRepository.readApiKey(profile.id);
    final response = await aiService.completeWithTools(
      profile: profile.copyWith(stream: false, maxTokens: 64),
      apiKey: apiKey,
      messages: const [
        {'role': 'user', 'content': 'Call the ping_test tool exactly once.'},
      ],
      tools: const [
        {
          'type': 'function',
          'function': {
            'name': 'ping_test',
            'description': 'Required connection test tool.',
            'parameters': {
              'type': 'object',
              'properties': {},
              'additionalProperties': false,
            },
          },
        },
      ],
    );
    return response.toolCalls.any((call) => call.name == 'ping_test');
  }

  Future<void> _handleEvent(MultiplayerEnvelope event) async {
    if (event.type != MultiplayerEventType.aiRequest || _profile == null)
      return;
    final requestId = event.payload['requestId'] as String?;
    if (requestId == null) return;
    try {
      final messages = (event.payload['messages'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
      final tools = (event.payload['tools'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
      final apiKey = await apiRepository.readApiKey(_profile!.id);
      final response = await aiService.completeWithTools(
        profile: _profile!.copyWith(stream: false),
        apiKey: apiKey,
        messages: messages,
        tools: tools,
      );
      requests++;
      await client.sendAIResponse(
        requestId: requestId,
        response: response.toJson(),
        inputTokens: response.inputTokens,
        outputTokens: response.outputTokens,
      );
    } catch (_) {
      errors++;
      await client.command(MultiplayerEventType.aiResponse, {
        'requestId': requestId,
        // Provider exceptions can contain URLs, headers or key fragments.
        // The relay needs a status, never local provider diagnostics.
        'error': 'AI_PROVIDER_FAILED',
      });
    }
  }

  Future<void> dispose() async {
    _heartbeat?.cancel();
    await _subscription?.cancel();
  }
}
