import 'dart:async';
import 'package:ai_tavern/models/api_profile.dart';
import 'package:ai_tavern/services/ai/ai_provider.dart';
import 'package:ai_tavern/services/ai/openai_compatible_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _StalledBodyClient extends http.BaseClient {
  final body = StreamController<List<int>>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(body.stream, 200);
  @override
  void close() {
    closed = true;
    body.close();
  }
}

void main() {
  test(
    'tool request times out after headers when response body never finishes, then closes client',
    () async {
      final client = _StalledBodyClient();
      final provider = OpenAICompatibleProvider(client: client);
      await expectLater(
        provider.completeWithTools(
          profile: const ApiProfile(
            id: 'test',
            name: 'test',
            baseUrl: 'https://example.invalid/v1',
            model: 'fake',
            timeoutSeconds: 1,
          ),
          apiKey: 'test',
          messages: const [],
          tools: const [],
        ),
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'AI_TIMEOUT')),
      );
      expect(client.closed, isTrue);
    },
  );
}
