import 'dart:convert';
import 'dart:io';

import 'package:ai_tavern/models/chat_attachment.dart';
import 'package:ai_tavern/models/vision_settings.dart';
import 'package:ai_tavern/services/vision/openai_compatible_vision_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('发送 OpenAI-Compatible 多模态请求并解析结构化结果', () async {
    final directory = await Directory.systemTemp.createTemp('vision_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}image.jpg');
    await file.writeAsBytes([1, 2, 3, 4]);

    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://vision.example/v1/chat/completions',
      );
      expect(request.headers['authorization'], 'Bearer vision-secret');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['model'], 'vision-model');
      final messages = body['messages']! as List;
      final content = (messages.single as Map)['content'] as List;
      final image = content.cast<Map>().last;
      expect(image['type'], 'image_url');
      expect(
        ((image['image_url'] as Map)['url'] as String),
        startsWith('data:image/jpeg;base64,'),
      );
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'summary': '一只猫',
                  'detailedDescription': '橘猫趴在窗边',
                  'detectedText': ' C A T ',
                  'people': <String>[],
                  'objects': ['窗户'],
                  'scene': '室内',
                  'mood': '安静',
                }),
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final provider = OpenAiCompatibleVisionProvider(
      settings: const VisionSettings(
        enabled: true,
        baseUrl: 'https://vision.example/v1',
        model: 'vision-model',
      ),
      apiKey: 'vision-secret',
      client: client,
    );
    addTearDown(provider.dispose);

    final analyses = await provider.analyzeImages([
      ChatAttachment(
        id: 'image-1',
        localPath: file.path,
        mimeType: 'image/jpeg',
        width: 1,
        height: 1,
        sizeBytes: 4,
      ),
    ], userQuestion: '这是什么？');

    expect(analyses, hasLength(1));
    expect(analyses.single.summary, '一只猫');
    expect(analyses.single.detailedDescription, '橘猫趴在窗边');
    expect(analyses.single.detectedText, 'C A T');
  });

  test('连接测试使用真实的 image_url 多模态格式', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      final messages = body['messages'] as List;
      final content = (messages.single as Map)['content'] as List;
      expect(
        content.any((part) => (part as Map)['type'] == 'image_url'),
        isTrue,
      );
      return http.Response(
        '{"choices":[{"message":{"content":"Vision OK"}}]}',
        200,
      );
    });
    final provider = OpenAiCompatibleVisionProvider(
      settings: const VisionSettings(
        enabled: true,
        baseUrl: 'https://vision.example/v1',
        model: 'vision-model',
      ),
      apiKey: '',
      client: client,
    );

    expect(await provider.testConnection(), 'Vision OK');
    provider.dispose();
  });
}
