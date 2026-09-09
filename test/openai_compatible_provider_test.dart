import 'package:ai_tavern/models/api_profile.dart';
import 'package:ai_tavern/services/ai/ai_provider.dart';
import 'package:ai_tavern/services/ai/openai_compatible_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const profile = ApiProfile(
    id: 'api-1',
    name: '测试',
    baseUrl: 'https://example.com/v1',
    model: 'test-model',
  );

  test('解析 OpenAI-Compatible SSE 流', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://example.com/v1/chat/completions');
      expect(request.headers['authorization'], 'Bearer secret');
      return http.Response(
        'data: {"choices":[{"delta":{"content":"你好"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"，旅行者"}}]}\n\n'
        'data: [DONE]\n\n',
        200,
        headers: {'content-type': 'text/event-stream; charset=utf-8'},
      );
    });

    final chunks = await OpenAICompatibleProvider(client: client)
        .streamChat(
          profile: profile,
          apiKey: 'secret',
          messages: const [
            {'role': 'user', 'content': '开始'},
          ],
        )
        .toList();

    expect(chunks.join(), '你好，旅行者');
  });

  test('HTTP 错误保留状态码与服务端消息', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"error":{"message":"API Key 无效"}}',
        401,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    expect(
      () => OpenAICompatibleProvider(client: client)
          .streamChat(profile: profile, apiKey: 'bad', messages: const [])
          .drain<void>(),
      throwsA(
        isA<AiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.message, 'message', contains('API Key')),
      ),
    );
  });

  test('非流式响应兼容数组 content 和 output_text', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"choices":[{"message":{"content":['
        '{"type":"output_text","text":"{\\"name\\":\\"测试卡\\"}"}'
        ']}}]}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final chunks = await OpenAICompatibleProvider(client: client)
        .streamChat(
          profile: profile.copyWith(stream: false),
          apiKey: 'secret',
          messages: const [],
        )
        .toList();

    expect(chunks.join(), '{"name":"测试卡"}');
  });

  test('没有标准正文时兼容 reasoning_content', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"choices":[{"message":{"content":null,'
        '"reasoning_content":"{\\"name\\":\\"推理卡\\"}"}}]}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final chunks = await OpenAICompatibleProvider(client: client)
        .streamChat(
          profile: profile.copyWith(stream: false),
          apiKey: 'secret',
          messages: const [],
        )
        .toList();

    expect(chunks.join(), '{"name":"推理卡"}');
  });

  test('流式正文为空时回退使用推理字段', () async {
    final client = MockClient(
      (_) async => http.Response(
        'data: {"choices":[{"delta":{"reasoning_content":"{\\"name\\":"}}]}\n\n'
        'data: {"choices":[{"delta":{"reasoning_content":"\\"流式推理卡\\"}"}}]}\n\n'
        'data: [DONE]\n\n',
        200,
        headers: {'content-type': 'text/event-stream; charset=utf-8'},
      ),
    );

    final chunks = await OpenAICompatibleProvider(client: client)
        .streamChat(profile: profile, apiKey: 'secret', messages: const [])
        .toList();

    expect(chunks.join(), '{"name":"流式推理卡"}');
  });

  test('标准 tool_calls 会被解析且工具 schema 被发送', () async {
    final client = MockClient((request) async {
      expect(request.body, contains('skill_check'));
      expect(request.body, contains('tool_choice'));
      return http.Response(
        '{"choices":[{"message":{"content":null,"tool_calls":['
        '{"id":"call-1","type":"function","function":{'
        '"name":"skill_check","arguments":"{\\"difficulty\\":12}"}}]}}]}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final response = await OpenAICompatibleProvider(client: client)
        .completeWithTools(
          profile: profile,
          apiKey: 'secret',
          messages: const [
            {'role': 'user', 'content': '潜行'},
          ],
          tools: const [
            {
              'type': 'function',
              'function': {
                'name': 'skill_check',
                'parameters': {'type': 'object'},
              },
            },
          ],
        );
    expect(response.toolCalls.single.id, 'call-1');
    expect(response.toolCalls.single.name, 'skill_check');
    expect(response.toolCalls.single.arguments['difficulty'], 12);
  });

  test('completeWithTools 兼容 reasoning_content 作为正文', () async {
    final client = MockClient((request) async {
      expect(request.body, isNot(contains('tool_choice')));
      expect(request.body, isNot(contains('"tools"')));
      return http.Response(
        '{"choices":[{"message":{"content":null,'
        '"reasoning_content":"阿黛尔在观察洛恩。"}}]}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final response = await OpenAICompatibleProvider(client: client)
        .completeWithTools(
          profile: profile,
          apiKey: 'secret',
          messages: const [
            {'role': 'user', 'content': '下一步'},
          ],
          tools: const [],
        );

    expect(response.content, '阿黛尔在观察洛恩。');
    expect(response.usedReasoningFallback, isTrue);
  });

  test('completeWithTools 兼容数组 content', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"choices":[{"message":{"content":['
        '{"type":"text","text":"阿黛尔直接走进仓库。"}'
        ']}}]}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final response = await OpenAICompatibleProvider(client: client)
        .completeWithTools(
          profile: profile,
          apiKey: 'secret',
          messages: const [
            {'role': 'user', 'content': '下一步'},
          ],
          tools: const [],
        );

    expect(response.content, '阿黛尔直接走进仓库。');
  });
}
