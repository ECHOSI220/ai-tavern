import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/chat_attachment.dart';
import '../../models/vision_analysis.dart';
import '../../models/vision_settings.dart';
import '../../utils/app_logger.dart';
import 'ocr_formatter.dart';
import 'vision_prompt_builder.dart';
import 'vision_provider.dart';

class OpenAiCompatibleVisionProvider implements VisionProvider {
  OpenAiCompatibleVisionProvider({
    required this.settings,
    required this.apiKey,
    http.Client? client,
    this._promptBuilder = const VisionPromptBuilder(),
    this._ocrFormatter = const OcrFormatter(),
  }) : _client = client ?? http.Client(),
       assert(settings.maxImages > 0);

  final VisionSettings settings;
  final String apiKey;
  final http.Client _client;
  final VisionPromptBuilder _promptBuilder;
  final OcrFormatter _ocrFormatter;
  var _disposed = false;

  @override
  Future<void> initialize() async {
    if (settings.provider != VisionProviderType.openAiCompatible) {
      throw VisionException('${settings.provider.label} 尚未实现');
    }
    if (settings.baseUrl.trim().isEmpty || settings.model.trim().isEmpty) {
      throw const VisionException('请先填写 Vision API 地址和模型名');
    }
  }

  @override
  Future<bool> isAvailable() async {
    return !_disposed &&
        settings.enabled &&
        settings.baseUrl.trim().isNotEmpty &&
        settings.model.trim().isNotEmpty;
  }

  @override
  Future<VisionAnalysis> analyzeImage(
    ChatAttachment image, {
    required String userQuestion,
  }) async {
    final result = await analyzeImages([image], userQuestion: userQuestion);
    return result.single;
  }

  @override
  Future<List<VisionAnalysis>> analyzeImages(
    List<ChatAttachment> images, {
    required String userQuestion,
  }) async {
    await initialize();
    if (images.isEmpty) return const [];
    if (images.length > settings.maxImages) {
      throw VisionException('一次最多分析 ${settings.maxImages} 张图片');
    }
    final analyses = <VisionAnalysis>[];
    for (final image in images) {
      analyses.add(await _analyzeOne(image, userQuestion));
    }
    return analyses;
  }

  Future<VisionAnalysis> _analyzeOne(
    ChatAttachment attachment,
    String userQuestion,
  ) async {
    final file = File(attachment.localPath);
    if (!await file.exists()) throw const VisionException('本地图片文件已丢失');
    final bytes = await file.readAsBytes();
    final dataUrl = 'data:${attachment.mimeType};base64,${base64Encode(bytes)}';
    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      'vision.request.start',
      fields: {
        'provider': 'openai-compatible',
        'model': settings.model,
        'bytes': bytes.length,
      },
    );
    try {
      final response = await _client
          .post(
            _endpoint(settings.baseUrl),
            headers: {
              'Content-Type': 'application/json',
              if (apiKey.trim().isNotEmpty)
                'Authorization': 'Bearer ${apiKey.trim()}',
            },
            body: jsonEncode({
              'model': settings.model.trim(),
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'text',
                      'text': _promptBuilder.build(
                        userQuestion: userQuestion,
                        ocrEnabled: settings.ocrEnabled,
                      ),
                    },
                    {
                      'type': 'image_url',
                      'image_url': {'url': dataUrl, 'detail': 'auto'},
                    },
                  ],
                },
              ],
              'temperature': 0.1,
              'max_tokens': 1800,
              'stream': false,
            }),
          )
          .timeout(Duration(seconds: settings.timeoutSeconds));
      AppLogger.info(
        'vision.response.status',
        fields: {'status': response.statusCode},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw VisionException(
          _serverMessage(response.body),
          statusCode: response.statusCode,
        );
      }
      final root = _jsonObject(response.body);
      final content = _content(root);
      final analysis = _decodeAnalysis(content);
      if (analysis.isEmpty) throw const VisionException('视觉模型没有返回可用内容');
      return VisionAnalysis(
        summary: analysis.summary,
        detailedDescription: analysis.detailedDescription,
        detectedText: settings.ocrEnabled
            ? _ocrFormatter.normalize(analysis.detectedText)
            : '',
        people: analysis.people,
        objects: analysis.objects,
        scene: analysis.scene,
        mood: analysis.mood,
        composition: analysis.composition,
        safetyNotes: analysis.safetyNotes,
      );
    } on TimeoutException {
      throw const VisionException('图片分析超时');
    } on http.ClientException catch (error) {
      throw VisionException('图片分析网络失败：${error.message}');
    } finally {
      stopwatch.stop();
      AppLogger.info(
        'vision.request.complete',
        fields: {'elapsedMs': stopwatch.elapsedMilliseconds},
      );
    }
  }

  @override
  Future<String> testConnection() async {
    await initialize();
    final response = await _client
        .post(
          _endpoint(settings.baseUrl),
          headers: {
            'Content-Type': 'application/json',
            if (apiKey.trim().isNotEmpty)
              'Authorization': 'Bearer ${apiKey.trim()}',
          },
          body: jsonEncode({
            'model': settings.model.trim(),
            'messages': [
              {
                'role': 'user',
                'content': const [
                  {'type': 'text', 'text': '识别这张测试图片，只回复 Vision OK'},
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url':
                          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAEAQH/6X2yAAAAAElFTkSuQmCC',
                      'detail': 'low',
                    },
                  },
                ],
              },
            ],
            'max_tokens': 20,
            'stream': false,
          }),
        )
        .timeout(Duration(seconds: settings.timeoutSeconds));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VisionException(
        _serverMessage(response.body),
        statusCode: response.statusCode,
      );
    }
    final reply = _content(_jsonObject(response.body)).trim();
    return reply.isEmpty ? '连接成功' : reply;
  }

  Uri _endpoint(String baseUrl) {
    final value = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final endpoint = value.endsWith('/chat/completions')
        ? value
        : '$value/chat/completions';
    final uri = Uri.tryParse(endpoint);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const VisionException('Vision API 地址格式不正确');
    }
    return uri;
  }

  Map<String, Object?> _jsonObject(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const VisionException('Vision API 返回格式无效');
    return decoded.cast<String, Object?>();
  }

  String _content(Map<String, Object?> root) {
    final choices = root['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) return '';
    final choice = (choices.first as Map).cast<String, Object?>();
    final message = choice['message'];
    if (message is! Map) return '';
    final content = message['content'];
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map>()
          .map((part) => part['text']?.toString() ?? '')
          .join();
    }
    return '';
  }

  VisionAnalysis _decodeAnalysis(String source) {
    var value = source.trim();
    value = value.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
      '',
    );
    if (value.startsWith('```')) {
      value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      value = value.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start >= 0 && end > start) value = value.substring(start, end + 1);
    try {
      return VisionAnalysis.fromJson(_jsonObject(value));
    } catch (_) {
      return VisionAnalysis(summary: source.trim());
    }
  }

  String _serverMessage(String body) {
    try {
      final root = _jsonObject(body);
      final error = root['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
      return root['message']?.toString() ?? '视觉服务请求失败';
    } catch (_) {
      return '视觉服务请求失败';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
  }
}
