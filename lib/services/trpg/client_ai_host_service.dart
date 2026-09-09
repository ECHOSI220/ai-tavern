// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';

import '../../models/api_profile.dart';
import '../../models/multiplayer_models.dart';
import '../ai_service.dart';
import '../ai/ai_provider.dart';
import '../../utils/app_logger.dart';
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
  String? _activeRequestId;
  final Set<String> _finishedRequests = {};
  int _generation = 0;
  bool _disposed = false;
  int requests = 0, errors = 0;

  Future<void> activate(ApiProfile profile) async {
    _generation++;
    aiService.cancel();
    _activeRequestId = null;
    _disposed = false;
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
    if (_disposed ||
        event.type != MultiplayerEventType.aiRequest ||
        _profile == null)
      return;
    final requestId = event.payload['requestId'] as String?;
    if (requestId == null ||
        requestId == _activeRequestId ||
        _finishedRequests.contains(requestId))
      return;
    final generation = ++_generation;
    aiService.cancel();
    _activeRequestId = requestId;
    final profile = _profile!;
    bool current() => !_disposed && generation == _generation;
    final watch = Stopwatch()..start();
    AppLogger.info('multiplayer.ai.start', fields: {'requestId': requestId});
    try {
      final messages = (event.payload['messages'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
      final tools = (event.payload['tools'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
      final apiKey = await apiRepository
          .readApiKey(profile.id)
          .timeout(const Duration(seconds: 10));
      if (!current()) return;
      final response = await aiService.completeWithTools(
        profile: profile.copyWith(
          stream: false,
          timeoutSeconds: profile.timeoutSeconds <= 0
              ? 120
              : profile.timeoutSeconds.clamp(15, 120),
        ),
        apiKey: apiKey,
        messages: messages,
        tools: tools,
      );
      if (!current()) return;
      requests++;
      await client.sendAIResponse(
        requestId: requestId,
        response: response.toJson(),
        inputTokens: response.inputTokens,
        outputTokens: response.outputTokens,
      );
    } catch (error) {
      if (!current()) return;
      errors++;
      final code =
          error is TimeoutException ||
              (error is AiException && error.code == 'AI_TIMEOUT')
          ? 'AI_TIMEOUT'
          : error is AiException &&
                const {
                  'AI_DNS_FAILED',
                  'AI_NETWORK_FAILED',
                }.contains(error.code)
          ? error.code!
          : 'AI_PROVIDER_FAILED';
      AppLogger.info(
        'multiplayer.ai.failed',
        fields: {
          'requestId': requestId,
          'code': code,
          'stage': error is AiException ? 'provider' : 'client_or_transport',
          'errorType': error.runtimeType.toString(),
          if (error is AiException) 'httpStatus': error.statusCode,
          'elapsedMs': watch.elapsedMilliseconds,
        },
      );
      try {
        await client.command(MultiplayerEventType.aiResponse, {
          'requestId': requestId,
          // Provider exceptions can contain URLs, headers or key fragments.
          // The relay needs a status, never local provider diagnostics.
          'error': code,
        });
      } catch (_) {
        /* The server deadline also recovers disconnected hosts. */
      }
    } finally {
      if (current()) {
        _activeRequestId = null;
        _finishedRequests.add(requestId);
        if (_finishedRequests.length > 64)
          _finishedRequests.remove(_finishedRequests.first);
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    aiService.cancel();
    _heartbeat?.cancel();
    await _subscription?.cancel();
  }
}
