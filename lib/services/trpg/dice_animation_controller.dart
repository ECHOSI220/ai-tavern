import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/trpg_dice_models.dart';

enum DiceAnimationPhase { idle, preparing, appearing, rolling, stopped, result }

class DiceSound {
  const DiceSound();

  Future<void> playRoll(DiceSettings settings) => _play(settings, light: true);
  Future<void> playBounce(DiceSettings settings) => _play(settings);
  Future<void> playResult(DiceSuccessLevel level, DiceSettings settings) async {
    if (settings.soundEnabled) {
      await SystemSound.play(
        level == DiceSuccessLevel.criticalSuccess
            ? SystemSoundType.alert
            : SystemSoundType.click,
      );
    }
    if (!settings.hapticsEnabled) return;
    switch (level) {
      case DiceSuccessLevel.criticalSuccess:
        await HapticFeedback.heavyImpact();
      case DiceSuccessLevel.criticalFailure:
        await HapticFeedback.vibrate();
      case DiceSuccessLevel.greatSuccess:
      case DiceSuccessLevel.success:
        await HapticFeedback.mediumImpact();
      case DiceSuccessLevel.failure:
      case DiceSuccessLevel.unopposed:
        await HapticFeedback.lightImpact();
    }
  }

  Future<void> _play(DiceSettings settings, {bool light = false}) async {
    if (settings.soundEnabled) await SystemSound.play(SystemSoundType.click);
    if (settings.hapticsEnabled) {
      await (light
          ? HapticFeedback.selectionClick()
          : HapticFeedback.lightImpact());
    }
  }
}

class DiceAnimationController extends ChangeNotifier {
  DiceAnimationController([this._sound = const DiceSound()]);

  final DiceSound _sound;
  final Random _random = Random();
  Timer? _ticker;
  DiceAnimationPhase phase = DiceAnimationPhase.idle;
  DiceRollResult? result;
  int displayNumber = 1;
  List<int> displayNumbers = const [1];
  double rotationTurns = 0;

  Future<void> play(
    DiceRollResult value,
    DiceSettings settings, {
    Duration phaseDuration = const Duration(milliseconds: 220),
    Duration rollingDuration = const Duration(milliseconds: 850),
  }) async {
    result = value;
    displayNumber = 1;
    final diceCount = max(1, value.individualResults.length);
    displayNumbers = List.filled(diceCount, 1);
    rotationTurns = 0;
    if (!settings.animationEnabled) {
      phase = DiceAnimationPhase.result;
      displayNumber = value.finalResult;
      displayNumbers = value.individualResults.isEmpty
          ? [value.baseResult == 0 ? value.finalResult : value.baseResult]
          : List.of(value.individualResults);
      notifyListeners();
      await _sound.playResult(value.successLevel, settings);
      return;
    }
    await _phase(DiceAnimationPhase.preparing, phaseDuration);
    await _sound.playRoll(settings);
    await _phase(DiceAnimationPhase.appearing, phaseDuration);
    phase = DiceAnimationPhase.rolling;
    notifyListeners();
    var ticks = 0;
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final match = RegExp(
        r'D(\d+)',
        caseSensitive: false,
      ).firstMatch(value.diceType);
      final sides = int.tryParse(match?.group(1) ?? '') ?? 20;
      if (ticks++ % 5 == 0) {
        displayNumbers = List.generate(
          diceCount,
          (_) => _random.nextInt(sides) + 1,
        );
        displayNumber = displayNumbers.first;
      }
      rotationTurns += .055;
      notifyListeners();
    });
    await Future<void>.delayed(rollingDuration);
    _ticker?.cancel();
    displayNumber = value.finalResult;
    displayNumbers = value.individualResults.isEmpty
        ? [value.baseResult == 0 ? value.finalResult : value.baseResult]
        : List.of(value.individualResults);
    phase = DiceAnimationPhase.stopped;
    notifyListeners();
    await _sound.playBounce(settings);
    await _settle(phaseDuration);
    phase = DiceAnimationPhase.result;
    notifyListeners();
    await _sound.playResult(value.successLevel, settings);
  }

  Future<void> _phase(DiceAnimationPhase next, Duration duration) async {
    phase = next;
    notifyListeners();
    await Future<void>.delayed(duration);
  }

  Future<void> _settle(Duration duration) async {
    if (duration == Duration.zero) return;
    final frames = max(1, duration.inMilliseconds ~/ 16);
    for (var frame = 0; frame < frames; frame++) {
      final remaining = 1 - frame / frames;
      rotationTurns += .055 * remaining * remaining;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
