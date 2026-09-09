import 'voice_settings.dart';

enum PresentationEventType {
  sceneBackground,
  characterShow,
  characterHide,
  characterExpression,
  characterPosition,
  bgmPlay,
  bgmStop,
  ambientPlay,
  ambientStop,
  sfxPlay,
  screenTransition,
  screenShake,
  diceAnimation,
  skillCheckAnimation,
  damageAnimation,
  healAnimation,
  itemGainAnimation,
  questUpdateAnimation,
  combatStart,
  combatEnd,
  dialogue,
}

enum NPCExpression {
  neutral,
  happy,
  angry,
  sad,
  fear,
  surprised,
  thinking,
  injured,
}

enum PortraitPosition { left, center, right }

enum SceneTransitionStyle { fade, crossfade, black, slide }

enum PresentationMode { classicChat, immersive }

enum PresentationQuality { simple, standard, full }

enum PresentationSpeakerType { narrator, npc, player, system }

enum CampaignVisualTheme { fantasy, horror, modern, scifi, custom }

enum AudioAssetType { bgm, ambient, sfx }

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((value) => value.name == raw).firstOrNull ?? fallback;

Map<String, Object?> _map(Object? raw) => raw is Map
    ? raw.map((key, value) => MapEntry(key.toString(), value))
    : const <String, Object?>{};

class PresentationEvent {
  const PresentationEvent({
    required this.eventId,
    required this.type,
    required this.sequenceNumber,
    required this.createdAt,
    this.payload = const {},
    this.critical = false,
    this.durationMs = 700,
  });

  final String eventId;
  final PresentationEventType type;
  final int sequenceNumber;
  final DateTime createdAt;
  final Map<String, Object?> payload;
  final bool critical;
  final int durationMs;

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'type': type.name,
    'sequenceNumber': sequenceNumber,
    'createdAt': createdAt.toIso8601String(),
    'payload': payload,
    'critical': critical,
    'durationMs': durationMs,
  };

  factory PresentationEvent.fromJson(Map<String, Object?> json) =>
      PresentationEvent(
        eventId: json['eventId'] as String? ?? '',
        type: _enumValue(
          PresentationEventType.values,
          json['type'],
          PresentationEventType.dialogue,
        ),
        sequenceNumber: (json['sequenceNumber'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        payload: _map(json['payload']),
        critical: json['critical'] as bool? ?? false,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 700,
      );
}

class VisibleCharacterState {
  const VisibleCharacterState({
    required this.npcId,
    this.portrait,
    this.expression = NPCExpression.neutral,
    this.position = PortraitPosition.center,
  });

  final String npcId;
  final String? portrait;
  final NPCExpression expression;
  final PortraitPosition position;

  VisibleCharacterState copyWith({
    String? portrait,
    NPCExpression? expression,
    PortraitPosition? position,
  }) => VisibleCharacterState(
    npcId: npcId,
    portrait: portrait ?? this.portrait,
    expression: expression ?? this.expression,
    position: position ?? this.position,
  );

  Map<String, Object?> toJson() => {
    'npcId': npcId,
    'portrait': portrait,
    'expression': expression.name,
    'position': position.name,
  };

  factory VisibleCharacterState.fromJson(Map<String, Object?> json) =>
      VisibleCharacterState(
        npcId: json['npcId'] as String? ?? '',
        portrait: json['portrait'] as String?,
        expression: _enumValue(
          NPCExpression.values,
          json['expression'],
          NPCExpression.neutral,
        ),
        position: _enumValue(
          PortraitPosition.values,
          json['position'],
          PortraitPosition.center,
        ),
      );
}

class CurrentPresentationState {
  const CurrentPresentationState({
    this.background,
    this.backgroundId,
    this.visibleCharacters = const [],
    this.bgmId,
    this.ambientId,
    this.sceneBgmId,
    this.presentationMode = PresentationMode.immersive,
    this.quality = PresentationQuality.standard,
    this.transitionStyle = SceneTransitionStyle.crossfade,
    this.combatActive = false,
    this.combatRound = 0,
    this.sequenceNumber = 0,
  });

  final String? background, backgroundId, bgmId, ambientId, sceneBgmId;
  final List<VisibleCharacterState> visibleCharacters;
  final PresentationMode presentationMode;
  final PresentationQuality quality;
  final SceneTransitionStyle transitionStyle;
  final bool combatActive;
  final int combatRound, sequenceNumber;

  CurrentPresentationState copyWith({
    String? background,
    String? backgroundId,
    List<VisibleCharacterState>? visibleCharacters,
    String? bgmId,
    String? ambientId,
    String? sceneBgmId,
    PresentationMode? presentationMode,
    PresentationQuality? quality,
    SceneTransitionStyle? transitionStyle,
    bool? combatActive,
    int? combatRound,
    int? sequenceNumber,
    bool clearBgm = false,
    bool clearAmbient = false,
  }) => CurrentPresentationState(
    background: background ?? this.background,
    backgroundId: backgroundId ?? this.backgroundId,
    visibleCharacters: visibleCharacters ?? this.visibleCharacters,
    bgmId: clearBgm ? null : bgmId ?? this.bgmId,
    ambientId: clearAmbient ? null : ambientId ?? this.ambientId,
    sceneBgmId: sceneBgmId ?? this.sceneBgmId,
    presentationMode: presentationMode ?? this.presentationMode,
    quality: quality ?? this.quality,
    transitionStyle: transitionStyle ?? this.transitionStyle,
    combatActive: combatActive ?? this.combatActive,
    combatRound: combatRound ?? this.combatRound,
    sequenceNumber: sequenceNumber ?? this.sequenceNumber,
  );

  Map<String, Object?> toJson() => {
    'background': background,
    'backgroundId': backgroundId,
    'visibleCharacters': visibleCharacters
        .map((value) => value.toJson())
        .toList(),
    'bgmId': bgmId,
    'ambientId': ambientId,
    'sceneBgmId': sceneBgmId,
    'presentationMode': presentationMode.name,
    'quality': quality.name,
    'transitionStyle': transitionStyle.name,
    'combatActive': combatActive,
    'combatRound': combatRound,
    'sequenceNumber': sequenceNumber,
  };

  factory CurrentPresentationState.fromJson(Map<String, Object?> json) =>
      CurrentPresentationState(
        background: json['background'] as String?,
        backgroundId: json['backgroundId'] as String?,
        visibleCharacters: (json['visibleCharacters'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (value) =>
                  VisibleCharacterState.fromJson(value.cast<String, Object?>()),
            )
            .toList(),
        bgmId: json['bgmId'] as String?,
        ambientId: json['ambientId'] as String?,
        sceneBgmId: json['sceneBgmId'] as String?,
        presentationMode: _enumValue(
          PresentationMode.values,
          json['presentationMode'],
          PresentationMode.immersive,
        ),
        quality: _enumValue(
          PresentationQuality.values,
          json['quality'],
          PresentationQuality.standard,
        ),
        transitionStyle: _enumValue(
          SceneTransitionStyle.values,
          json['transitionStyle'],
          SceneTransitionStyle.crossfade,
        ),
        combatActive: json['combatActive'] as bool? ?? false,
        combatRound: (json['combatRound'] as num?)?.toInt() ?? 0,
        sequenceNumber: (json['sequenceNumber'] as num?)?.toInt() ?? 0,
      );
}

class MessagePresentationMetadata {
  const MessagePresentationMetadata({
    this.speakerType = PresentationSpeakerType.system,
    this.speakerId,
    this.expression = NPCExpression.neutral,
    this.autoSpeak = true,
  });

  final PresentationSpeakerType speakerType;
  final String? speakerId;
  final NPCExpression expression;
  final bool autoSpeak;

  Map<String, Object?> toJson() => {
    'speakerType': speakerType.name,
    'speakerId': speakerId,
    'expression': expression.name,
    'autoSpeak': autoSpeak,
  };

  factory MessagePresentationMetadata.fromJson(Map<String, Object?> json) =>
      MessagePresentationMetadata(
        speakerType: _enumValue(
          PresentationSpeakerType.values,
          json['speakerType'],
          PresentationSpeakerType.system,
        ),
        speakerId: json['speakerId'] as String?,
        expression: _enumValue(
          NPCExpression.values,
          json['expression'],
          NPCExpression.neutral,
        ),
        autoSpeak: json['autoSpeak'] as bool? ?? true,
      );
}

class AudioAsset {
  const AudioAsset({
    required this.id,
    required this.type,
    required this.path,
    this.tags = const [],
    this.volume = 1,
    this.loop = true,
  });

  final String id, path;
  final AudioAssetType type;
  final List<String> tags;
  final double volume;
  final bool loop;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'path': path,
    'tags': tags,
    'volume': volume,
    'loop': loop,
  };

  factory AudioAsset.fromJson(Map<String, Object?> json) => AudioAsset(
    id: json['id'] as String? ?? '',
    type: _enumValue(AudioAssetType.values, json['type'], AudioAssetType.sfx),
    path: json['path'] as String? ?? '',
    tags: (json['tags'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(),
    volume: ((json['volume'] as num?)?.toDouble() ?? 1).clamp(0, 1),
    loop: json['loop'] as bool? ?? true,
  );
}

class CampaignPresentationSettings {
  const CampaignPresentationSettings({
    this.defaultBgm,
    this.defaultAmbient,
    this.defaultNarratorVoice = const CharacterVoiceConfig(),
    this.transitionStyle = SceneTransitionStyle.crossfade,
    this.uiTheme = CampaignVisualTheme.modern,
  });

  final String? defaultBgm, defaultAmbient;
  final CharacterVoiceConfig defaultNarratorVoice;
  final SceneTransitionStyle transitionStyle;
  final CampaignVisualTheme uiTheme;

  Map<String, Object?> toJson() => {
    'defaultBgm': defaultBgm,
    'defaultAmbient': defaultAmbient,
    'defaultNarratorVoice': defaultNarratorVoice.toJson(),
    'transitionStyle': transitionStyle.name,
    'uiTheme': uiTheme.name,
  };

  factory CampaignPresentationSettings.fromJson(Map<String, Object?> json) =>
      CampaignPresentationSettings(
        defaultBgm: json['defaultBgm'] as String?,
        defaultAmbient: json['defaultAmbient'] as String?,
        defaultNarratorVoice: json['defaultNarratorVoice'] is Map
            ? CharacterVoiceConfig.fromJson(
                (json['defaultNarratorVoice'] as Map).cast<String, Object?>(),
              )
            : const CharacterVoiceConfig(),
        transitionStyle: _enumValue(
          SceneTransitionStyle.values,
          json['transitionStyle'],
          SceneTransitionStyle.crossfade,
        ),
        uiTheme: _enumValue(
          CampaignVisualTheme.values,
          json['uiTheme'],
          CampaignVisualTheme.modern,
        ),
      );
}
