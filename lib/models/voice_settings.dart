enum SpeechLanguageMode { auto, chinese, english }

enum SpeechInputMode { tapToStop, vadAutoStop }

enum SpeechInsertMode { append, replace }

class CharacterVoiceConfig {
  const CharacterVoiceConfig({
    this.enabled = true,
    this.provider = 'system_mandarin',
    this.voiceId = '0',
    this.speed = 1,
    this.volume = 1,
    this.pitch = 1,
    this.languageMode = SpeechLanguageMode.auto,
    this.autoSpeak = false,
  });

  final bool enabled;
  final String provider;
  final String voiceId;
  final double speed;
  final double volume;
  final double pitch;
  final SpeechLanguageMode languageMode;
  final bool autoSpeak;

  CharacterVoiceConfig copyWith({
    bool? enabled,
    String? provider,
    String? voiceId,
    double? speed,
    double? volume,
    double? pitch,
    SpeechLanguageMode? languageMode,
    bool? autoSpeak,
  }) => CharacterVoiceConfig(
    enabled: enabled ?? this.enabled,
    provider: provider ?? this.provider,
    voiceId: voiceId ?? this.voiceId,
    speed: (speed ?? this.speed).clamp(0.5, 2),
    volume: (volume ?? this.volume).clamp(0, 1),
    pitch: (pitch ?? this.pitch).clamp(0.5, 2),
    languageMode: languageMode ?? this.languageMode,
    autoSpeak: autoSpeak ?? this.autoSpeak,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'provider': provider,
    'voiceId': voiceId,
    'speed': speed,
    'volume': volume,
    'pitch': pitch,
    'languageMode': languageMode.name,
    'autoSpeak': autoSpeak,
  };

  factory CharacterVoiceConfig.fromJson(Map<String, Object?> json) {
    final legacyKokoro = json['provider'] == 'sherpa_kokoro';
    return CharacterVoiceConfig(
      enabled: json['enabled'] as bool? ?? true,
      provider: 'system_mandarin',
      voiceId: legacyKokoro ? '0' : json['voiceId'] as String? ?? '0',
      speed: ((json['speed'] as num?)?.toDouble() ?? 1).clamp(0.5, 2),
      volume: ((json['volume'] as num?)?.toDouble() ?? 1).clamp(0, 1),
      pitch: ((json['pitch'] as num?)?.toDouble() ?? 1).clamp(0.5, 2),
      languageMode: SpeechLanguageMode.values.byName(
        json['languageMode'] as String? ?? 'auto',
      ),
      autoSpeak: json['autoSpeak'] as bool? ?? false,
    );
  }
}

class VoiceSettings {
  const VoiceSettings({
    this.speechInputEnabled = false,
    this.recognitionLanguage = SpeechLanguageMode.auto,
    this.inputMode = SpeechInputMode.vadAutoStop,
    this.autoSend = false,
    this.insertMode = SpeechInsertMode.append,
    this.ttsEnabled = false,
    this.autoSpeak = false,
    this.defaultTtsProvider = 'system_mandarin',
    this.defaultVoiceId = '0',
    this.defaultSpeed = 1,
    this.defaultVolume = 1,
    this.speakNarration = true,
    this.vadThreshold = 0.5,
    this.speechEndSilenceSeconds = 0.8,
    this.maxRecordingSeconds = 60,
    this.characterOverrides = const {},
  });

  final bool speechInputEnabled;
  final SpeechLanguageMode recognitionLanguage;
  final SpeechInputMode inputMode;
  final bool autoSend;
  final SpeechInsertMode insertMode;
  final bool ttsEnabled;
  final bool autoSpeak;
  final String defaultTtsProvider;
  final String defaultVoiceId;
  final double defaultSpeed;
  final double defaultVolume;
  final bool speakNarration;
  final double vadThreshold;
  final double speechEndSilenceSeconds;
  final int maxRecordingSeconds;
  final Map<String, CharacterVoiceConfig> characterOverrides;

  CharacterVoiceConfig voiceFor(String? characterId) {
    final override = characterId == null
        ? null
        : characterOverrides[characterId];
    return override ??
        CharacterVoiceConfig(
          provider: defaultTtsProvider,
          voiceId: defaultVoiceId,
          speed: defaultSpeed,
          volume: defaultVolume,
          autoSpeak: autoSpeak,
        );
  }

  VoiceSettings copyWith({
    bool? speechInputEnabled,
    SpeechLanguageMode? recognitionLanguage,
    SpeechInputMode? inputMode,
    bool? autoSend,
    SpeechInsertMode? insertMode,
    bool? ttsEnabled,
    bool? autoSpeak,
    String? defaultTtsProvider,
    String? defaultVoiceId,
    double? defaultSpeed,
    double? defaultVolume,
    bool? speakNarration,
    double? vadThreshold,
    double? speechEndSilenceSeconds,
    int? maxRecordingSeconds,
    Map<String, CharacterVoiceConfig>? characterOverrides,
  }) => VoiceSettings(
    speechInputEnabled: speechInputEnabled ?? this.speechInputEnabled,
    recognitionLanguage: recognitionLanguage ?? this.recognitionLanguage,
    inputMode: inputMode ?? this.inputMode,
    autoSend: autoSend ?? this.autoSend,
    insertMode: insertMode ?? this.insertMode,
    ttsEnabled: ttsEnabled ?? this.ttsEnabled,
    autoSpeak: autoSpeak ?? this.autoSpeak,
    defaultTtsProvider: defaultTtsProvider ?? this.defaultTtsProvider,
    defaultVoiceId: defaultVoiceId ?? this.defaultVoiceId,
    defaultSpeed: (defaultSpeed ?? this.defaultSpeed).clamp(0.5, 2),
    defaultVolume: (defaultVolume ?? this.defaultVolume).clamp(0, 1),
    speakNarration: speakNarration ?? this.speakNarration,
    vadThreshold: (vadThreshold ?? this.vadThreshold).clamp(0.1, 0.9),
    speechEndSilenceSeconds:
        (speechEndSilenceSeconds ?? this.speechEndSilenceSeconds).clamp(0.3, 3),
    maxRecordingSeconds: (maxRecordingSeconds ?? this.maxRecordingSeconds)
        .clamp(10, 120),
    characterOverrides: characterOverrides ?? this.characterOverrides,
  );

  Map<String, Object?> toJson() => {
    'speechInputEnabled': speechInputEnabled,
    'recognitionLanguage': recognitionLanguage.name,
    'inputMode': inputMode.name,
    'autoSend': autoSend,
    'insertMode': insertMode.name,
    'ttsEnabled': ttsEnabled,
    'autoSpeak': autoSpeak,
    'defaultTtsProvider': defaultTtsProvider,
    'defaultVoiceId': defaultVoiceId,
    'defaultSpeed': defaultSpeed,
    'defaultVolume': defaultVolume,
    'speakNarration': speakNarration,
    'vadThreshold': vadThreshold,
    'speechEndSilenceSeconds': speechEndSilenceSeconds,
    'maxRecordingSeconds': maxRecordingSeconds,
    'characterOverrides': characterOverrides.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };

  factory VoiceSettings.fromJson(Map<String, Object?> json) {
    final rawOverrides = json['characterOverrides'];
    final overrides = <String, CharacterVoiceConfig>{};
    if (rawOverrides is Map) {
      for (final entry in rawOverrides.entries) {
        if (entry.key is String && entry.value is Map) {
          overrides[entry.key as String] = CharacterVoiceConfig.fromJson(
            (entry.value as Map).cast<String, Object?>(),
          );
        }
      }
    }
    T enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) =>
        values.where((item) => item.name == raw).firstOrNull ?? fallback;
    return VoiceSettings(
      speechInputEnabled: json['speechInputEnabled'] as bool? ?? false,
      recognitionLanguage: enumValue(
        SpeechLanguageMode.values,
        json['recognitionLanguage'],
        SpeechLanguageMode.auto,
      ),
      inputMode: enumValue(
        SpeechInputMode.values,
        json['inputMode'],
        SpeechInputMode.vadAutoStop,
      ),
      autoSend: json['autoSend'] as bool? ?? false,
      insertMode: enumValue(
        SpeechInsertMode.values,
        json['insertMode'],
        SpeechInsertMode.append,
      ),
      ttsEnabled: json['ttsEnabled'] as bool? ?? false,
      autoSpeak: json['autoSpeak'] as bool? ?? false,
      defaultTtsProvider: 'system_mandarin',
      defaultVoiceId: '0',
      defaultSpeed: (json['defaultSpeed'] as num?)?.toDouble() ?? 1,
      defaultVolume: (json['defaultVolume'] as num?)?.toDouble() ?? 1,
      speakNarration: json['speakNarration'] as bool? ?? true,
      vadThreshold: (json['vadThreshold'] as num?)?.toDouble() ?? 0.5,
      speechEndSilenceSeconds:
          (json['speechEndSilenceSeconds'] as num?)?.toDouble() ?? 0.8,
      maxRecordingSeconds: json['maxRecordingSeconds'] as int? ?? 60,
      characterOverrides: overrides,
    );
  }
}
