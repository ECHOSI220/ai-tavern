class AIGMOutputGuard {
  const AIGMOutputGuard._();

  static bool isDisplayableChinese(String value) {
    final text = value.trim();
    if (text.isEmpty || looksLikeInternalAnalysis(text)) return false;

    final chineseCount = RegExp(r'[\u3400-\u9fff]').allMatches(text).length;
    final latinCount = RegExp(r'[A-Za-z]').allMatches(text).length;
    if (text.length >= 80 && chineseCount < 12) return false;
    if (latinCount > 80 && latinCount > chineseCount * 2) return false;
    return true;
  }

  static bool looksLikeInternalAnalysis(String value) {
    final lower = value.trim().toLowerCase();
    const markers = [
      'let me ',
      'i need to ',
      'we need to ',
      'looking at ',
      'structured state',
      'current player action',
      'the user ',
      'based on the ',
      'my reasoning',
    ];
    return markers.any(lower.contains);
  }
}
