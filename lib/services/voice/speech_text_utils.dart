import '../../models/voice_settings.dart';

String mergeRecognizedText({
  required String existing,
  required String recognized,
  required SpeechInsertMode mode,
}) {
  final incoming = recognized.trim();
  if (mode == SpeechInsertMode.replace || existing.trim().isEmpty) {
    return incoming;
  }
  final current = existing.trimRight();
  if (incoming.isEmpty) return current;
  final needsSpace =
      RegExp(r'[A-Za-z0-9]$').hasMatch(current) &&
      RegExp(r'^[A-Za-z0-9]').hasMatch(incoming);
  return '$current${needsSpace ? ' ' : ''}$incoming';
}

String sanitizeForSpeech(String source, {bool speakNarration = true}) {
  var text = source;
  text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
  text = text.replaceAll(
    RegExp(r'^(?:#{1,6}|>|[-*+]\s+)\s*', multiLine: true),
    '',
  );
  text = text.replaceAll(RegExp(r'[\uFE0E\uFE0F\u200D]'), '');
  text = text.replaceAll(RegExp(r'[*_`~]'), '');
  if (!speakNarration) {
    text = text.replaceAll(RegExp(r'[（(][^）)]*[）)]'), ' ');
  }
  text = text.replaceAll(
    RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true),
    '',
  );
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

List<String> splitSpeechSentences(String source) {
  final text = source.trim();
  if (text.isEmpty) return const [];
  final result = <String>[];
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    if ('。！？.!?\n'.contains(text[i])) {
      final sentence = text.substring(start, i + 1).trim();
      if (sentence.isNotEmpty) result.add(sentence);
      start = i + 1;
    }
  }
  final tail = text.substring(start).trim();
  if (tail.isNotEmpty) result.add(tail);
  return result;
}
