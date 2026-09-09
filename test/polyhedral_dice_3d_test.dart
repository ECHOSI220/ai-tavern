import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_tavern/models/trpg_dice_models.dart';
import 'package:ai_tavern/app/skins/theme_catalog.dart';
import 'package:ai_tavern/app/skins/theme_manager.dart';
import 'package:ai_tavern/screens/trpg_shared/dice_panel.dart';
import 'package:ai_tavern/screens/trpg_shared/polyhedral_dice_3d.dart';
import 'package:ai_tavern/services/trpg/dice_animation_controller.dart';
import 'package:ai_tavern/services/trpg/dice_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'theme_skin_system_test.dart' show MemoryThemeStore, harness;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('polyhedral meshes expose the correct number of numbered faces', () {
    for (final sides in [4, 6, 8, 10, 12, 20]) {
      expect(
        PolyhedralDicePainter.faceCountForSides(sides),
        sides,
        reason: 'D$sides must use a real $sides-face mesh',
      );
    }
  });

  test(
    'animation settles on every raw die rather than the modified total',
    () async {
      final result = DiceEngine().evaluate(
        formula: const DiceFormula(diceCount: 2, sides: 6, modifier: 3),
        individualResults: const [2, 5],
        playerId: 'p1',
      );
      final controller = DiceAnimationController();
      await controller.play(
        result,
        const DiceSettings(soundEnabled: false, hapticsEnabled: false),
        phaseDuration: Duration.zero,
        rollingDuration: const Duration(milliseconds: 4),
      );
      expect(controller.displayNumbers, [2, 5]);
      expect(controller.displayNumber, 10);
      controller.dispose();
    },
  );

  test(
    'animation emits rolling, bounce, and decelerating landing frames',
    () async {
      final result = DiceEngine().evaluate(
        formula: const DiceFormula(diceCount: 1, sides: 20),
        individualResults: const [18],
        playerId: 'p1',
      );
      final controller = DiceAnimationController();
      final phases = <DiceAnimationPhase>[];
      final turns = <double>[];
      controller.addListener(() {
        phases.add(controller.phase);
        turns.add(controller.rotationTurns);
      });
      await controller.play(
        result,
        const DiceSettings(soundEnabled: false, hapticsEnabled: false),
        phaseDuration: const Duration(milliseconds: 96),
        rollingDuration: const Duration(milliseconds: 180),
      );

      expect(phases, contains(DiceAnimationPhase.rolling));
      expect(phases, contains(DiceAnimationPhase.stopped));
      expect(phases.last, DiceAnimationPhase.result);
      expect(turns.toSet().length, greaterThan(10));
      expect(turns.last, greaterThan(.3));
      expect(controller.displayNumbers, [18]);
      controller.dispose();
    },
  );

  testWidgets('D4 D6 D8 D10 D12 D20 and percentile dice render in 3D', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final font = File('C:/Windows/Fonts/msyh.ttc');
      if (await font.exists()) {
        final data = ByteData.sublistView(await font.readAsBytes());
        for (final family in ['Ahem', 'Roboto', 'Microsoft YaHei']) {
          await (FontLoader(family)..addFont(Future.value(data))).load();
        }
      }
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xff080d1c),
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: const Color(0xff080d1c),
              child: Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 18,
                  runSpacing: 20,
                  children: [
                    for (final entry in const [
                      (4, 3),
                      (6, 5),
                      (8, 7),
                      (10, 9),
                      (12, 11),
                      (20, 18),
                      (100, 73),
                    ])
                      SizedBox(
                        width: entry.$1 == 100 ? 260 : 190,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'D${entry.$1}',
                              style: const TextStyle(
                                color: Color(0xffffd77b),
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                            Dice3DStage(
                              sides: entry.$1,
                              values: [entry.$2],
                              rotationTurns: .37,
                              color: const Color(0xff3f7cc8),
                              settled: true,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('polyhedral-dice-3d-stage')),
      findsNWidgets(7),
    );
    expect(find.bySemanticsLabel('旋转的 20 面骰，当前点数 18'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/dice_3d_review').create(recursive: true);
      await File(
        'build/dice_3d_review/polyhedral-dice.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });

  testWidgets('result dialog shows raw faces, modifier, and final total', (
    tester,
  ) async {
    final result = DiceEngine().evaluate(
      formula: const DiceFormula(diceCount: 2, sides: 6, modifier: 3),
      individualResults: const [2, 5],
      playerId: '玩家',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => DiceResultDialog(
                result: result,
                settings: const DiceSettings(
                  animationEnabled: false,
                  soundEnabled: false,
                  hapticsEnabled: false,
                ),
              ),
            ),
            child: const Text('投骰'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('投骰'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('polyhedral-dice-3d-stage')),
      findsOneWidget,
    );
    expect(find.text('骰面 2 + 5 + 3 ＝ 10'), findsOneWidget);
    expect(find.byKey(const ValueKey('dice-3d-d6-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('dice-3d-d6-5')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('render the real narrow knight-theme D100 result dialog', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final manager = ThemeManager(MemoryThemeStore());
    addTearDown(manager.dispose);
    await manager.applyTheme(ThemeCatalog.byId('knight_oath_mooncourt').id);
    final boundary = GlobalKey();
    final result = DiceEngine().evaluate(
      formula: const DiceFormula(diceCount: 1, sides: 100),
      individualResults: const [73],
      playerId: '玩家',
      difficulty: 60,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: harness(
          manager,
          Scaffold(
            body: DiceResultDialog(
              result: result,
              settings: const DiceSettings(
                animationEnabled: false,
                soundEnabled: false,
                hapticsEnabled: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tens = tester.getRect(find.byKey(const ValueKey('dice-3d-d10-70')));
    final ones = tester.getRect(find.byKey(const ValueKey('dice-3d-d10-3')));
    expect(tens.center.dy, closeTo(ones.center.dy, 1));
    expect(tens.right, lessThan(ones.left));
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'build/dice_3d_review/result-dialog-d100.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
