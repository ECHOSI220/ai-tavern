import 'package:ai_tavern/services/choice_generation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = ChoiceGenerationService();

  test('解析模型返回的 JSON 数组并保持设定数量', () {
    final result = service.parseAndFill(
      '以下是结果：["检查脚印","询问白雪","查看制服","尝试起身"]',
      4,
    );

    expect(result, ['检查脚印', '询问白雪', '查看制服', '尝试起身']);
  });

  test('兼容编号列表、去重并用本地选项补足', () {
    final result = service.parseAndFill('1. 检查脚印\n2. 检查脚印\n3. 询问白雪', 6);

    expect(result, hasLength(6));
    expect(result.take(2), ['检查脚印', '询问白雪']);
    expect(result.toSet(), hasLength(6));
  });

  test('完全无法解析时仍给出指定数量的可玩选项', () {
    expect(service.fallback(2), hasLength(2));
    expect(service.fallback(10), hasLength(10));
  });

  test('细化提示要求保持原数量并同时生成角色动作与具体台词', () {
    final prompt = service.refinementInstruction(
      currentChoices: const ['询问她昨晚去了哪里', '检查桌上的钥匙'],
      count: 6,
      playerName: '洛恩',
    );

    expect(prompt, contains('恰好 6 个'));
    expect(prompt, contains('洛恩 本人的动作'));
    expect(prompt, contains('说出的具体台词'));
    expect(prompt, contains('询问她昨晚去了哪里'));
  });

  test('细化接口返回不足时用带动作和台词的选项补足', () {
    final fallback = service.refinementFallback(
      currentChoices: const ['检查房门', '询问同伴'],
      count: 4,
      playerName: '洛恩',
    );
    final result = service.parseAndFill(
      '["洛恩上前半步，压低声音：“先让我看看门锁。”"]',
      4,
      fallbackChoices: fallback,
    );

    expect(result, hasLength(4));
    expect(result.every((item) => item.contains('洛恩')), isTrue);
    expect(result.every((item) => item.contains('“')), isTrue);
  });
}
