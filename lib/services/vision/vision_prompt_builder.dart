class VisionPromptBuilder {
  const VisionPromptBuilder();

  String build({required String userQuestion, required bool ocrEnabled}) {
    final question = userQuestion.trim();
    return '''你是一个为角色扮演聊天提供画面理解的视觉工具。
请客观分析图片，不要续写剧情，不要猜测看不清的细节。不确定时明确说“可能”或“无法确认”。
重点识别：
1. 画面主体和场景环境
2. 人物的可见外观、服饰、动作和表情
3. 重要物品、空间关系和画面构图
4. 画面氛围与可见的事件
${ocrEnabled ? '5. 提取所有可辨认文字（OCR），保留原文顺序' : '5. 不需专门进行 OCR'}
${question.isEmpty ? '用户没有附加问题，请提供适合角色自然回应的画面信息。' : '用户同时说：“$question”\n请优先观察与这句话最相关的细节。'}

只输出一个合法 JSON 对象，不要 Markdown 或分析过程：
{
  "summary":"简短总结",
  "detailedDescription":"客观细节",
  "detectedText":"可见文字，没有则为空字符串",
  "people":["人物信息"],
  "objects":["重要物品"],
  "scene":"场景",
  "mood":"氛围与表情",
  "composition":"构图与位置关系",
  "safetyNotes":"不确定性或无法识别之处"
}''';
  }
}
