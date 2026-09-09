import 'package:ai_tavern/models/vision_analysis.dart';
import 'package:ai_tavern/services/vision/vision_context_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('将结构化视觉结果转换为角色可自然使用的隐藏上下文', () {
    final result = const VisionContextFormatter().format(const [
      VisionAnalysis(
        summary: '一名白发少女站在雪地里',
        detectedText: 'WARNING',
        people: ['白发少女，神情警惕'],
        objects: ['长枪'],
        scene: '夜晚的雪原',
      ),
    ], userText: '她在看什么？');

    expect(result, contains('[用户发送了一张图片]'));
    expect(result, contains('可见文字：WARNING'));
    expect(result, contains('用户同时说'));
    expect(result, contains('不要提到视觉模型'));
  });
}
