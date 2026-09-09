import '../../models/trpg_memory_models.dart';
import 'memory_ranker.dart';

class TokenEstimator {
  const TokenEstimator();
  int estimate(String text) {
    final han = RegExp(r'[\u3400-\u9fff]').allMatches(text).length;
    final remainder = text.length - han;
    return han + (remainder / 4).ceil();
  }
}

class MemoryContextBuilder {
  const MemoryContextBuilder({this.estimator = const TokenEstimator()});
  final TokenEstimator estimator;

  String build(Iterable<RankedMemory> ranked, {required int tokenBudget}) {
    final lines = <String>['【与当前场景相关的长期记忆】'];
    var tokens = estimator.estimate(lines.first);
    for (final item in ranked) {
      final memory = item.memory;
      final confidence = switch (memory.confidence) {
        MemoryConfidence.confirmed => '事实',
        MemoryConfidence.likely => '较可能',
        MemoryConfidence.uncertain => '不确定推测',
      };
      final belief = memory.canonPriority == CanonPriority.npcBelief
          ? 'NPC认知'
          : confidence;
      final line =
          '- [$belief] ${memory.summary.isEmpty ? memory.content : memory.summary}${memory.resolved ? '（已解决）' : ''}';
      final cost = estimator.estimate(line);
      if (tokens + cost > tokenBudget) continue;
      lines.add(line);
      tokens += cost;
    }
    return lines.length == 1 ? '' : lines.join('\n');
  }
}
