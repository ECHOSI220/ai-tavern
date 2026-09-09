import 'package:ai_tavern/models/rule_reference.dart';
import 'package:ai_tavern/screens/rule_library/rule_library_screen.dart';
import 'package:ai_tavern/services/trpg/rule_compendium.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compendium exposes useful entries for every supported section', () {
    for (final system in RuleReferenceSystem.values) {
      expect(
        RuleCompendium.search(system: system),
        isNotEmpty,
        reason: '${system.label} should never open as an empty library',
      );
      expect(RuleCompendium.categoriesFor(system), isNotEmpty);
    }
  });

  test(
    'search matches title, body and aliases without leaking other systems',
    () {
      final sanity = RuleCompendium.search(
        system: RuleReferenceSystem.coc7,
        query: 'SAN 疯狂',
      );
      expect(sanity.map((entry) => entry.id), ['coc-sanity']);

      final dnd = RuleCompendium.search(
        system: RuleReferenceSystem.dnd5e,
        query: '专注 体质豁免',
      );
      expect(dnd.map((entry) => entry.id), ['dnd-spell']);

      expect(
        RuleCompendium.search(system: RuleReferenceSystem.dnd5e, query: '理智'),
        isEmpty,
      );
    },
  );

  testWidgets('library switches systems and filters results on mobile', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: const RuleLibraryScreen(),
      ),
    );

    expect(find.text('D20 检定与难度'), findsOneWidget);
    await tester.tap(find.text('COC 7版').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('rule-library-search')),
      '理智 疯狂',
    );
    await tester.pump();

    expect(find.text('理智检定与疯狂'), findsOneWidget);
    expect(find.byKey(const ValueKey('rule-entry-coc-sanity')), findsOneWidget);
    expect(find.text('D20 检定与难度'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick start includes the required three-part opening guidance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const RuleLibraryScreen(
          initialSystem: RuleReferenceSystem.quickStart,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('rule-library-search')),
      '世界观 人物 当前事件',
    );
    await tester.pump();

    expect(find.text('三段式开场说明'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
