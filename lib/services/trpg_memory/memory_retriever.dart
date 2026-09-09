import '../../models/trpg_memory_models.dart';
import 'memory_privacy_filter.dart';
import 'memory_ranker.dart';

abstract interface class EmbeddingProvider {
  Future<List<double>> embed(String text);
}

class MemoryRetriever {
  const MemoryRetriever({
    this.privacyFilter = const MemoryPrivacyFilter(),
    this.ranker = const MemoryRanker(),
  });
  final MemoryPrivacyFilter privacyFilter;
  final MemoryRanker ranker;

  List<RankedMemory> retrieve({
    required Iterable<MemoryEntry> memories,
    required MemoryRetrievalContext context,
    required MemoryAccessContext access,
  }) => ranker.rank(privacyFilter.filter(memories, access), context);
}
