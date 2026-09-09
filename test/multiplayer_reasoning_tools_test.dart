import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tavern/services/ai/openai_compatible_provider.dart';

void main() {
  test('reasoning with tool calls is not a reasoning-only answer', () {
    final response = OpenAIChatResponse.fromJson({
      'choices': [
        {
          'message': {
            'content': null,
            'reasoning_content': 'private tool reasoning',
            'tool_calls': [
              {
                'id': 'clock',
                'type': 'function',
                'function': {
                  'name': 'advance_time',
                  'arguments': '{"minutes":5}',
                },
              },
            ],
          },
        },
      ],
    });
    expect(response.content, isEmpty);
    expect(response.usedReasoningFallback, isFalse);
    expect(response.toolCalls.single.name, 'advance_time');
    final restored = OpenAIChatResponse.fromTransportJson(response.toJson());
    expect(restored.reasoningContent, 'private tool reasoning');
    expect(restored.content, isEmpty);
  });
  test('reasoning-only answer remains flagged', () {
    final response = OpenAIChatResponse.fromJson({
      'choices': [
        {
          'message': {'content': null, 'reasoning_content': 'private'},
        },
      ],
    });
    expect(response.usedReasoningFallback, isTrue);
  });
}
