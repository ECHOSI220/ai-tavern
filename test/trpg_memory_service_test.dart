import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/services/trpg/trpg_memory_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TRPG memory keeps recent messages and summarizes older narration', () {
    final now = DateTime.utc(2026, 8, 13);
    final session = TRPGSession(
      id: 'memory',
      title: '记忆测试',
      mode: TRPGMode.solo,
      createdAt: now,
      updatedAt: now,
      lastPlayedAt: now,
      campaignId: 'mist_harbor_test',
      chatHistory: List.generate(
        45,
        (index) => TRPGMessage(
          id: '$index',
          messageType: index.isEven
              ? TRPGMessageType.playerMessage
              : TRPGMessageType.gmMessage,
          content: '第 $index 条港口调查叙事',
          createdAt: now.add(Duration(minutes: index)),
        ),
      ),
    );
    const memory = TRPGMemoryService(recentMessageLimit: 30);
    final compacted = memory.compact(session);
    expect(memory.selectRecentMessages(compacted), hasLength(30));
    expect(compacted.sessionSummary, contains('第 0 条港口调查叙事'));
    expect(compacted.sessionSummary, contains('第 14 条港口调查叙事'));
    expect(compacted.sessionSummary, isNot(contains('第 44 条港口调查叙事')));
    // Numeric state is untouched by narrative compaction.
    expect(compacted.campaignState.toJson(), session.campaignState.toJson());
  });
}
