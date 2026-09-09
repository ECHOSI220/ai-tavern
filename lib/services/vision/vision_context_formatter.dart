import '../../models/vision_analysis.dart';

class VisionContextFormatter {
  const VisionContextFormatter();

  String format(List<VisionAnalysis> analyses, {required String userText}) {
    final buffer = StringBuffer()
      ..writeln(
        '[用户发送了${analyses.length > 1 ? '${analyses.length} 张' : '一张'}图片]',
      )
      ..writeln('以下是你在画面中能够观察到的信息：');
    for (var index = 0; index < analyses.length; index++) {
      final item = analyses[index];
      buffer.writeln(
        '\n${analyses.length > 1 ? '图片 ${index + 1}' : '图片观察结果'}：',
      );
      _line(buffer, '概要', item.summary);
      _line(buffer, '场景', item.scene);
      _line(buffer, '人物', item.people.join('；'));
      _line(buffer, '动作/表情/氛围', item.mood);
      _line(buffer, '物品', item.objects.join('；'));
      _line(buffer, '可见文字', item.detectedText);
      _line(buffer, '其他细节', item.detailedDescription);
      _line(buffer, '不确定信息', item.safetyNotes);
    }
    if (userText.trim().isNotEmpty) {
      buffer
        ..writeln('\n用户同时说：')
        ..writeln('“${userText.trim()}”');
    }
    buffer.writeln(
      '\n请把这些信息当作你亲眼看到的画面，继续扮演当前角色并自然回应。'
      '不要提到视觉模型、图片分析、OCR、JSON 或系统工具；'
      '不要机械复述整份报告，而要回答用户并继续当前剧情。',
    );
    return buffer.toString().trim();
  }

  void _line(StringBuffer buffer, String label, String value) {
    if (value.trim().isNotEmpty) buffer.writeln('$label：${value.trim()}');
  }
}
