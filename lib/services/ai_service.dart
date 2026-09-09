import '../models/api_profile.dart';
import 'ai/ai_provider.dart';
import 'ai/openai_compatible_provider.dart';

typedef ToolChatResponse = OpenAIChatResponse;

class AiService {
  AiProvider? _activeProvider;

  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    final provider = OpenAICompatibleProvider();
    _activeProvider = provider;
    try {
      yield* provider.streamChat(
        profile: profile,
        apiKey: apiKey,
        messages: messages,
      );
    } finally {
      if (identical(_activeProvider, provider)) _activeProvider = null;
    }
  }

  Future<AiTestResult> testConnection({
    required ApiProfile profile,
    required String apiKey,
  }) {
    return OpenAICompatibleProvider().testConnection(
      profile: profile,
      apiKey: apiKey,
    );
  }

  Future<ToolChatResponse> completeWithTools({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
  }) async {
    final provider = OpenAICompatibleProvider();
    _activeProvider = provider;
    try {
      return await provider.completeWithTools(
        profile: profile,
        apiKey: apiKey,
        messages: messages,
        tools: tools,
      );
    } finally {
      if (identical(_activeProvider, provider)) _activeProvider = null;
    }
  }

  void cancel() {
    _activeProvider?.cancel();
    _activeProvider = null;
  }
}
