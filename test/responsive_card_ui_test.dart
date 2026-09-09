import 'package:ai_tavern/models/app_mode.dart';
import 'package:ai_tavern/models/campaign_models.dart';
import 'package:ai_tavern/screens/campaigns/campaign_library_screen.dart';
import 'package:ai_tavern/screens/platform_home/platform_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _largeTextHost(Widget child) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: MediaQuery(
    data: const MediaQueryData(
      size: Size(390, 844),
      textScaler: TextScaler.linear(1.8),
    ),
    child: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SizedBox(width: 358, child: child),
      ),
    ),
  ),
);

void main() {
  testWidgets('mode card grows instead of clipping its recent session text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _largeTextHost(
        PlatformModeCard(
          mode: AppMode.soloTrpg,
          icon: Icons.explore_outlined,
          description: '由 AI 担任主持人的个人冒险',
          recentTitle: '第七次圣杯战争：冬木残响',
          recentDetail: '第 1 幕 · 陌生旅店里的召唤之夜',
          onTap: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final card = tester.getRect(
      find.byKey(const ValueKey('mode-card-soloTrpg')),
    );
    final detail = tester.getRect(find.text('第 1 幕 · 陌生旅店里的召唤之夜'));
    expect(detail.bottom, lessThan(card.bottom - 8));
  });

  testWidgets('campaign placeholder stays separate from title at large text', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 21);
    final campaign = CampaignDocument(
      id: 'holy-grail-ui-test',
      title: '第七次圣杯战争：冬木残响',
      theme: '现代都市魔术战争',
      ruleSystem: 'Holy Grail War TRPG',
      recommendedPlayers: '1~7',
      estimatedLength: '12~40小时',
      author: '幻境酒馆',
      tags: const ['圣杯战争', '都市奇幻', '阵营博弈'],
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      _largeTextHost(
        CampaignLibraryCard(
          campaign: campaign,
          compact: true,
          onTap: () {},
          onMenuSelected: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final icon = tester.getRect(find.byIcon(Icons.auto_stories_outlined));
    final title = tester.getRect(find.text('第七次圣杯战争：冬木残响'));
    expect(icon.overlaps(title), isFalse);
  });
}
