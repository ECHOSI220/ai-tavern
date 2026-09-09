import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/trpg_models.dart';
import '../../models/trpg_presentation_models.dart';

class TRPGPresentationService extends ChangeNotifier {
  TRPGPresentationService({CurrentPresentationState? initialState})
    : _state = initialState ?? const CurrentPresentationState();

  static const _uuid = Uuid();
  final _pending = <PresentationEvent>[];
  final _events = StreamController<PresentationEvent>.broadcast();
  CurrentPresentationState _state;
  PresentationEvent? _active;
  bool _running = false;
  bool _skipCurrent = false;

  CurrentPresentationState get state => _state;
  PresentationEvent? get active => _active;
  Stream<PresentationEvent> get events => _events.stream;
  int get pendingCount => _pending.length;

  PresentationEvent create(
    PresentationEventType type, {
    Map<String, Object?> payload = const {},
    bool critical = false,
    int durationMs = 700,
  }) => PresentationEvent(
    eventId: _uuid.v4(),
    type: type,
    sequenceNumber: _state.sequenceNumber + _pending.length + 1,
    createdAt: DateTime.now(),
    payload: payload,
    critical: critical,
    durationMs: durationMs,
  );

  Future<void> enqueue(PresentationEvent event) async {
    if (event.sequenceNumber <= _state.sequenceNumber) return;
    _pending.add(event);
    _pending.sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    notifyListeners();
    await _drain();
  }

  Future<void> enqueueAll(Iterable<PresentationEvent> events) async {
    for (final event in events) {
      if (event.sequenceNumber > _state.sequenceNumber) _pending.add(event);
    }
    _pending.sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    notifyListeners();
    await _drain();
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_pending.isNotEmpty) {
        final event = _pending.removeAt(0);
        _active = event;
        _skipCurrent = false;
        _state = reduce(_state, event);
        _events.add(event);
        notifyListeners();
        final duration = _effectiveDuration(event);
        for (
          var elapsed = 0;
          elapsed < duration && !_skipCurrent;
          elapsed += 40
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        _active = null;
        notifyListeners();
      }
    } finally {
      _running = false;
    }
  }

  int _effectiveDuration(PresentationEvent event) {
    if (_state.quality == PresentationQuality.simple && !event.critical) {
      return 0;
    }
    if (_state.quality == PresentationQuality.full) return event.durationMs;
    return (event.durationMs * .65).round();
  }

  void skip() {
    if (_active?.critical == true) return;
    _skipCurrent = true;
  }

  void fastForwardRead() {
    _skipCurrent = true;
    _pending.removeWhere((value) => !value.critical);
    notifyListeners();
  }

  void restore(CurrentPresentationState state) {
    _state = state;
    _pending.clear();
    notifyListeners();
  }

  static CurrentPresentationState reduce(
    CurrentPresentationState state,
    PresentationEvent event,
  ) {
    var next = state.copyWith(sequenceNumber: event.sequenceNumber);
    switch (event.type) {
      case PresentationEventType.sceneBackground:
        next = next.copyWith(
          background: event.payload['background'] as String?,
          backgroundId: event.payload['backgroundId'] as String?,
          sceneBgmId: event.payload['bgmId'] as String?,
        );
      case PresentationEventType.characterShow:
        final id = event.payload['npcId'] as String? ?? '';
        if (id.isEmpty) break;
        final expression = _enum(
          NPCExpression.values,
          event.payload['expression'],
          NPCExpression.neutral,
        );
        final position = _enum(
          PortraitPosition.values,
          event.payload['position'],
          PortraitPosition.center,
        );
        final visible = [
          ...next.visibleCharacters.where((value) => value.npcId != id),
        ];
        if (visible.length >= 3) visible.removeAt(0);
        visible.add(
          VisibleCharacterState(
            npcId: id,
            portrait: event.payload['portrait'] as String?,
            expression: expression,
            position: position,
          ),
        );
        next = next.copyWith(visibleCharacters: visible);
      case PresentationEventType.characterHide:
        final id = event.payload['npcId'] as String?;
        next = next.copyWith(
          visibleCharacters: id == null
              ? const []
              : next.visibleCharacters
                    .where((value) => value.npcId != id)
                    .toList(),
        );
      case PresentationEventType.characterExpression:
      case PresentationEventType.characterPosition:
        final id = event.payload['npcId'] as String? ?? '';
        next = next.copyWith(
          visibleCharacters: next.visibleCharacters.map((value) {
            if (value.npcId != id) return value;
            return value.copyWith(
              expression: _enum(
                NPCExpression.values,
                event.payload['expression'],
                value.expression,
              ),
              position: _enum(
                PortraitPosition.values,
                event.payload['position'],
                value.position,
              ),
            );
          }).toList(),
        );
      case PresentationEventType.bgmPlay:
        next = next.copyWith(bgmId: event.payload['assetId'] as String?);
      case PresentationEventType.bgmStop:
        next = next.copyWith(clearBgm: true);
      case PresentationEventType.ambientPlay:
        next = next.copyWith(ambientId: event.payload['assetId'] as String?);
      case PresentationEventType.ambientStop:
        next = next.copyWith(clearAmbient: true);
      case PresentationEventType.screenTransition:
        next = next.copyWith(
          transitionStyle: _enum(
            SceneTransitionStyle.values,
            event.payload['style'],
            state.transitionStyle,
          ),
        );
      case PresentationEventType.combatStart:
        next = next.copyWith(
          combatActive: true,
          combatRound: (event.payload['round'] as num?)?.toInt() ?? 1,
          bgmId: event.payload['bgmId'] as String? ?? 'battle',
        );
      case PresentationEventType.combatEnd:
        next = next.copyWith(
          combatActive: false,
          combatRound: 0,
          bgmId: next.sceneBgmId,
        );
      default:
        break;
    }
    return next;
  }

  static T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) =>
      values.where((value) => value.name == raw).firstOrNull ?? fallback;

  @override
  void dispose() {
    unawaited(_events.close());
    super.dispose();
  }
}

class AIPresentationDirector {
  const AIPresentationDirector();

  List<PresentationEvent> derive({
    required TRPGSession before,
    required TRPGSession after,
  }) {
    var sequence = before.presentationState.sequenceNumber;
    final events = <PresentationEvent>[];
    PresentationEvent add(
      PresentationEventType type,
      Map<String, Object?> payload, {
      bool critical = false,
      int durationMs = 700,
    }) {
      sequence++;
      return PresentationEvent(
        eventId: 'auto_${after.id}_$sequence',
        type: type,
        sequenceNumber: sequence,
        createdAt: DateTime.now(),
        payload: payload,
        critical: critical,
        durationMs: durationMs,
      );
    }

    if (before.currentScene != after.currentScene ||
        before.worldState.location != after.worldState.location) {
      events
        ..add(
          add(PresentationEventType.screenTransition, {
            'style': SceneTransitionStyle.crossfade.name,
          }),
        )
        ..add(
          add(PresentationEventType.sceneBackground, {
            'backgroundId': after.currentScene,
            'background': after.presentationState.background,
            'bgmId': after.presentationState.sceneBgmId,
          }),
        );
    }
    final oldEvents = before.eventLog.map((value) => value.id).toSet();
    for (final event in after.eventLog.where(
      (value) => !oldEvents.contains(value.id),
    )) {
      // 暗骰和无演出检定只进入服务端权威状态，不得在玩家端
      // 弹出动画泄露检定的存在或结果。
      if (event.payload['visibility'] == 'gmHidden' ||
          event.payload['presentationMode'] == 'none' ||
          (event.payload['decision'] is Map &&
              (event.payload['decision'] as Map)['presentationMode'] ==
                  'none')) {
        continue;
      }
      final mapped = switch (event.type) {
        TRPGEventType.diceRoll => PresentationEventType.diceAnimation,
        TRPGEventType.skillCheck => PresentationEventType.skillCheckAnimation,
        TRPGEventType.itemGain => PresentationEventType.itemGainAnimation,
        TRPGEventType.questUpdate => PresentationEventType.questUpdateAnimation,
        TRPGEventType.hpChange || TRPGEventType.damageApplied =>
          ((event.payload['amount'] as num?)?.toInt() ?? 0) > 0
              ? PresentationEventType.healAnimation
              : PresentationEventType.damageAnimation,
        TRPGEventType.combatStarted => PresentationEventType.combatStart,
        TRPGEventType.combatEnded => PresentationEventType.combatEnd,
        _ => null,
      };
      if (mapped != null) {
        events.add(
          add(
            mapped,
            event.payload,
            critical:
                mapped == PresentationEventType.diceAnimation ||
                mapped == PresentationEventType.skillCheckAnimation ||
                mapped == PresentationEventType.combatStart ||
                mapped == PresentationEventType.combatEnd,
            durationMs: 1050,
          ),
        );
      }
    }
    final oldMessages = before.chatHistory.map((value) => value.id).toSet();
    for (final message in after.chatHistory.where(
      (value) => !oldMessages.contains(value.id),
    )) {
      if (message.presentation.speakerType == PresentationSpeakerType.npc &&
          message.presentation.speakerId != null) {
        events.add(
          add(PresentationEventType.characterShow, {
            'npcId': message.presentation.speakerId,
            'expression': message.presentation.expression.name,
            'position': PortraitPosition.center.name,
          }),
        );
      }
      events.add(
        add(PresentationEventType.dialogue, {
          'messageId': message.id,
          'content': message.content,
          ...message.presentation.toJson(),
        }, durationMs: 350),
      );
    }
    return events;
  }
}
