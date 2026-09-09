import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/api_profile.dart';
import '../../utils/app_logger.dart';
import 'ai_provider.dart';
import 'platform_proxy_client.dart';

class OpenAICompatibleProvider implements AiProvider {
  OpenAICompatibleProvider({http.Client? client})
    : _client = client ?? createPlatformProxyClient();

  final http.Client _client;
  var _cancelled = false;

  Future<OpenAIChatResponse> completeWithTools({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> tools,
  }) async {
    final request = http.Request('POST', _endpoint(profile.baseUrl))
      ..headers.addAll(_headers(profile.copyWith(stream: false), apiKey))
      ..body = jsonEncode({
        'model': profile.model,
        'messages': messages,
        'temperature': profile.temperature,
        'top_p': profile.topP,
        'max_tokens': profile.maxTokens,
        'stream': false,
        if (tools.isNotEmpty) ...{'tools': tools, 'tool_choice': 'auto'},
      });
    final watch = Stopwatch()..start();
    final timeout = Duration(
      seconds: profile.timeoutSeconds <= 0 ? 120 : profile.timeoutSeconds,
    );
    AppLogger.info('ai.tools.start');
    try {
      return await (() async {
        final response = await _client.send(request);
        AppLogger.info(
          'ai.tools.headers',
          fields: {
            'status': response.statusCode,
            'elapsedMs': watch.elapsedMilliseconds,
          },
        );
        final body = await response.stream.bytesToString();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw _httpException(response.statusCode, body);
        }
        return OpenAIChatResponse.fromJson(_decodeObject(body));
      })().timeout(timeout);
    } on TimeoutException {
      throw const AiException('模型完整回复超时，行动已保留，请重试结算。', code: 'AI_TIMEOUT');
    } on http.ClientException catch (error) {
      final dns = error.message.contains('Failed host lookup');
      throw AiException(
        dns ? 'DNS 无法解析模型地址，请检查当前网络或系统代理。' : '模型连接中断，请检查网络或系统代理。',
        code: dns ? 'AI_DNS_FAILED' : 'AI_NETWORK_FAILED',
      );
    } finally {
      watch.stop();
      AppLogger.info(
        'ai.tools.complete',
        fields: {'elapsedMs': watch.elapsedMilliseconds},
      );
      _client.close();
    }
  }

  @override
  Stream<String> streamChat({
    required ApiProfile profile,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    _cancelled = false;
    final stopwatch = Stopwatch()..start();
    var statusCode = 0;
    var chunkCount = 0;
    AppLogger.info(
      'ai.request.start',
      fields: {'stream': profile.stream, 'model': profile.model},
    );
    try {
      final request = http.Request('POST', _endpoint(profile.baseUrl))
        ..headers.addAll(_headers(profile, apiKey))
        ..body = jsonEncode(
          _requestBody(profile, messages, stream: profile.stream),
        );
      final pendingResponse = _client.send(request);
      final response = profile.timeoutSeconds <= 0
          ? await pendingResponse
          : await pendingResponse.timeout(
              Duration(seconds: profile.timeoutSeconds),
            );
      statusCode = response.statusCode;
      AppLogger.info('ai.response.status', fields: {'status': statusCode});
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        throw _httpException(response.statusCode, body);
      }

      if (!profile.stream) {
        final body = await response.stream.bytesToString();
        final decoded = _decodeObject(body);
        final content = _messageContent(decoded);
        if (content.isNotEmpty) {
          chunkCount++;
          yield content;
        }
        return;
      }

      // Chat Completions 流一般是 SSE：每行 data: JSON，以 [DONE] 结束。
      final reasoningFallback = StringBuffer();
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (_cancelled) return;
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
        final data = trimmed.startsWith('data:')
            ? trimmed.substring(5).trim()
            : trimmed;
        if (data == '[DONE]') {
          if (chunkCount == 0 && reasoningFallback.isNotEmpty) {
            chunkCount++;
            yield reasoningFallback.toString();
          }
          return;
        }
        final decoded = _decodeObject(data);
        final content = _deltaContent(decoded);
        if (content.isNotEmpty) {
          chunkCount++;
          yield content;
        } else {
          final reasoning = _deltaReasoning(decoded);
          if (reasoning.isNotEmpty) reasoningFallback.write(reasoning);
        }
      }
      if (chunkCount == 0 && reasoningFallback.isNotEmpty) {
        chunkCount++;
        yield reasoningFallback.toString();
      }
    } on TimeoutException {
      AppLogger.error('ai.request.timeout', TimeoutException('timeout'));
      throw const AiException('连接超时，请检查 API 地址或网络');
    } on http.ClientException catch (error) {
      if (_cancelled) return;
      AppLogger.error('ai.request.network_error', error);
      throw AiException('网络请求失败：${error.message}');
    } on FormatException catch (error) {
      AppLogger.error('ai.response.parse_error', error);
      throw AiException('API 返回格式无法解析：${error.message}');
    } finally {
      stopwatch.stop();
      AppLogger.info(
        'ai.request.complete',
        fields: {
          'status': statusCode,
          'chunks': chunkCount,
          'cancelled': _cancelled,
          'elapsedMs': stopwatch.elapsedMilliseconds,
        },
      );
      _client.close();
    }
  }

  @override
  Future<AiTestResult> testConnection({
    required ApiProfile profile,
    required String apiKey,
  }) async {
    final stopwatch = Stopwatch()..start();
    var statusCode = 0;
    AppLogger.info(
      'ai.connection_test.start',
      fields: {'model': profile.model},
    );
    try {
      final request = http.Request('POST', _endpoint(profile.baseUrl))
        ..headers.addAll(_headers(profile, apiKey))
        ..body = jsonEncode({
          ..._requestBody(profile, const [
            {'role': 'user', 'content': 'Reply with exactly: Hello'},
          ], stream: false),
          'max_tokens': 32,
        });
      final response = await _client
          .send(request)
          .timeout(
            Duration(
              seconds: profile.timeoutSeconds <= 0
                  ? 60
                  : profile.timeoutSeconds,
            ),
          );
      statusCode = response.statusCode;
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _httpException(response.statusCode, body);
      }
      final decoded = _decodeObject(body);
      return AiTestResult(
        response: _messageContent(decoded),
        model: decoded['model'] as String?,
      );
    } on TimeoutException {
      AppLogger.error(
        'ai.connection_test.timeout',
        TimeoutException('timeout'),
      );
      throw const AiException('连接超时，请检查 API 地址或网络');
    } on http.ClientException catch (error) {
      AppLogger.error('ai.connection_test.network_error', error);
      throw AiException('网络请求失败：${error.message}');
    } on FormatException catch (error) {
      AppLogger.error('ai.connection_test.parse_error', error);
      throw AiException('API 返回格式无法解析：${error.message}');
    } finally {
      stopwatch.stop();
      AppLogger.info(
        'ai.connection_test.complete',
        fields: {
          'status': statusCode,
          'elapsedMs': stopwatch.elapsedMilliseconds,
        },
      );
      _client.close();
    }
  }

  @override
  void cancel() {
    _cancelled = true;
    _client.close();
  }

  Uri _endpoint(String baseUrl) {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) throw const AiException('API 地址不能为空');
    final value = trimmed.endsWith('/chat/completions')
        ? trimmed
        : '$trimmed/chat/completions';
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const AiException('API 地址格式不正确');
    }
    return uri;
  }

  Map<String, String> _headers(ApiProfile profile, String apiKey) => {
    'Content-Type': 'application/json',
    'Accept': profile.stream ? 'text/event-stream' : 'application/json',
    if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
    ...profile.extraHeaders,
  };

  Map<String, Object?> _requestBody(
    ApiProfile profile,
    List<Map<String, String>> messages, {
    required bool stream,
  }) => {
    'model': profile.model,
    'messages': messages,
    'temperature': profile.temperature,
    'top_p': profile.topP,
    'max_tokens': profile.maxTokens,
    'stream': stream,
  };

  Map<String, Object?> _decodeObject(String source) {
    final value = jsonDecode(source);
    if (value is! Map) throw const FormatException('根节点不是 JSON 对象');
    return value.cast<String, Object?>();
  }

  String _deltaContent(Map<String, Object?> json) {
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) return '';
    final choice = (choices.first as Map).cast<String, Object?>();
    final delta = choice['delta'];
    if (delta is Map) {
      final content = _contentValue(delta['content']);
      if (content.isNotEmpty) return content;
    }
    return _messageContent(json);
  }

  String _deltaReasoning(Map<String, Object?> json) {
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) return '';
    final choice = (choices.first as Map).cast<String, Object?>();
    final delta = choice['delta'];
    if (delta is! Map) return '';
    return _firstContent([
      delta['reasoning_content'],
      delta['reasoning'],
      delta['reasoning_text'],
    ]);
  }

  String _messageContent(Map<String, Object?> json) {
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final choice = (choices.first as Map).cast<String, Object?>();
      final message = choice['message'];
      if (message is Map) {
        final content = _firstContent([
          message['content'],
          message['output_text'],
          message['reasoning_content'],
          message['reasoning'],
          message['reasoning_text'],
        ]);
        if (content.isNotEmpty) return content;
      }
      final choiceContent = _firstContent([
        choice['text'],
        choice['content'],
        choice['output_text'],
        choice['reasoning_content'],
      ]);
      if (choiceContent.isNotEmpty) return choiceContent;
    }
    return _firstContent([
      json['output_text'],
      json['text'],
      json['content'],
      json['response'],
    ]);
  }

  String _firstContent(List<Object?> values) {
    for (final value in values) {
      final content = _contentValue(value);
      if (content.isNotEmpty) return content;
    }
    return '';
  }

  String _contentValue(Object? value) {
    if (value is String) return value;
    if (value is List) {
      final buffer = StringBuffer();
      for (final item in value) {
        if (item is String) {
          buffer.write(item);
        } else if (item is Map) {
          final map = item.cast<Object?, Object?>();
          final nested = map['text'] ?? map['content'] ?? map['output_text'];
          if (nested is String) buffer.write(nested);
        }
      }
      return buffer.toString();
    }
    if (value is Map) {
      final map = value.cast<Object?, Object?>();
      return _contentValue(map['text'] ?? map['content'] ?? map['output_text']);
    }
    return '';
  }

  AiException _httpException(int statusCode, String body) {
    var message = body.trim();
    try {
      final decoded = _decodeObject(body);
      final error = decoded['error'];
      if (error is Map && error['message'] is String) {
        message = error['message']! as String;
      } else if (decoded['message'] is String) {
        message = decoded['message']! as String;
      }
    } on FormatException {
      // 非 JSON 错误体保留原文摘要。
    }
    if (message.length > 500) message = '${message.substring(0, 500)}…';
    if (message.isEmpty) message = 'API 请求失败';
    return AiException(message, statusCode: statusCode);
  }
}

class OpenAIToolCall {
  const OpenAIToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
  final String id;
  final String name;
  final Map<String, Object?> arguments;

  factory OpenAIToolCall.fromJson(Map<String, Object?> json) {
    final function = json['function'] is Map
        ? (json['function'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final raw = function['arguments'];
    final arguments = raw is String
        ? (jsonDecode(raw) as Map).cast<String, Object?>()
        : raw is Map
        ? raw.cast<String, Object?>()
        : const <String, Object?>{};
    return OpenAIToolCall(
      id: json['id'] as String? ?? '',
      name: function['name'] as String? ?? '',
      arguments: arguments,
    );
  }

  Map<String, Object?> toAssistantJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': jsonEncode(arguments)},
  };
}

class OpenAIChatResponse {
  const OpenAIChatResponse({
    required this.content,
    required this.toolCalls,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.usedReasoningFallback = false,
    this.reasoningContent,
  });
  final String content;
  final List<OpenAIToolCall> toolCalls;
  final int inputTokens, outputTokens;

  /// True when the transport returned no final answer and [content] had to be
  /// recovered from a reasoning/thinking field. Callers that display text to
  /// users must repair or reject it instead of exposing internal analysis.
  final bool usedReasoningFallback;
  final String? reasoningContent;

  Map<String, Object?> toJson() => {
    'content': content,
    'toolCalls': toolCalls.map((call) => call.toAssistantJson()).toList(),
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'usedReasoningFallback': usedReasoningFallback,
    if (reasoningContent != null) 'reasoningContent': reasoningContent,
  };

  factory OpenAIChatResponse.fromTransportJson(Map<String, Object?> json) =>
      OpenAIChatResponse(
        content: json['content'] as String? ?? '',
        toolCalls: (json['toolCalls'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) => OpenAIToolCall.fromJson(item.cast<String, Object?>()),
            )
            .toList(),
        inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
        usedReasoningFallback: json['usedReasoningFallback'] == true,
        reasoningContent: json['reasoningContent'] as String?,
      );

  factory OpenAIChatResponse.fromJson(Map<String, Object?> json) {
    final choices = json['choices'] as List? ?? const [];
    if (choices.isEmpty || choices.first is! Map) {
      throw const FormatException('API 没有返回 choices');
    }
    final choice = (choices.first as Map).cast<String, Object?>();
    final message = choice['message'] is Map
        ? (choice['message'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final calls = (message['tool_calls'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => OpenAIToolCall.fromJson(item.cast<String, Object?>()))
        .toList();
    final standardContent = _extractStandardMessageContent(message, choice);
    final reasoningContent = _stringifyContent(
      message['reasoning_content'] ??
          message['reasoning'] ??
          message['reasoning_text'],
    );
    final content = standardContent.isNotEmpty || calls.isNotEmpty
        ? standardContent
        : reasoningContent;
    final usage = json['usage'] is Map
        ? (json['usage'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    return OpenAIChatResponse(
      content: content,
      toolCalls: calls,
      inputTokens:
          (usage['prompt_tokens'] as num?)?.toInt() ??
          (usage['input_tokens'] as num?)?.toInt() ??
          0,
      outputTokens:
          (usage['completion_tokens'] as num?)?.toInt() ??
          (usage['output_tokens'] as num?)?.toInt() ??
          0,
      usedReasoningFallback:
          calls.isEmpty &&
          standardContent.isEmpty &&
          reasoningContent.isNotEmpty,
      reasoningContent: message['reasoning_content'] is String
          ? message['reasoning_content'] as String
          : null,
    );
  }

  static String _extractStandardMessageContent(
    Map<String, Object?> message,
    Map<String, Object?> choice,
  ) {
    final content = _stringifyContent(message['content']);
    if (content.isNotEmpty) return content;
    final alternative = _stringifyContent(message['output_text']);
    if (alternative.isNotEmpty) return alternative;
    return _stringifyContent(
      choice['text'] ?? choice['content'] ?? choice['output_text'],
    );
  }

  static String _stringifyContent(Object? value) {
    if (value is String) return value;
    if (value is List) {
      final buffer = StringBuffer();
      for (final item in value) {
        if (item is String) {
          buffer.write(item);
        } else if (item is Map) {
          final map = item.cast<Object?, Object?>();
          buffer.write(
            _stringifyContent(
              map['text'] ?? map['content'] ?? map['output_text'],
            ),
          );
        }
      }
      return buffer.toString();
    }
    if (value is Map) {
      final map = value.cast<Object?, Object?>();
      return _stringifyContent(
        map['text'] ?? map['content'] ?? map['output_text'],
      );
    }
    return '';
  }
}
