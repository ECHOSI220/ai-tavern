import 'nsfw_prompt_template.dart';
import 'voice_settings.dart';
import 'vision_settings.dart';
import 'trpg_presentation_models.dart';

class AppSettings {
  const AppSettings({
    this.theme = 'dark',
    this.fontScale = 1,
    this.defaultApiProfileId,
    this.defaultTemperature = 0.9,
    this.historyMessageCount = 50,
    this.autoContextCompression = false,
    this.contextCompressionInterval = 6,
    this.nsfwEnabled = false,
    this.nsfwPromptTemplates = defaultNsfwPromptTemplates,
    this.voiceSettings = const VoiceSettings(),
    this.visionSettings = const VisionSettings(),
    this.streaming = true,
    this.showAvatars = true,
    this.autoScroll = true,
    this.debugMode = false,
    this.dialogueImmersionEnabled = true,
    this.trpgDefaultRule = 'simple_trpg',
    this.trpgAutoSave = true,
    this.trpgDiceAnimation = true,
    this.trpgDefaultGmProfileId,
    this.trpgGmOutputLength = 2000,
    this.trpgPresentationMode = PresentationMode.immersive,
    this.trpgPresentationQuality = PresentationQuality.standard,
    this.trpgAutoSpeakGm = false,
    this.trpgAutoSpeakNpc = true,
    this.trpgAutoSpeakNarrator = true,
    this.trpgMasterVolume = 1,
    this.trpgBgmVolume = .65,
    this.trpgAmbientVolume = .55,
    this.trpgSfxVolume = .85,
    this.trpgVoiceVolume = 1,
    this.trpgMemoryTokenBudget = 3000,
  });

  final String theme;
  final double fontScale;
  final String? defaultApiProfileId;
  final double defaultTemperature;
  final int historyMessageCount;
  final bool autoContextCompression;
  final int contextCompressionInterval;
  final bool nsfwEnabled;
  final List<NsfwPromptTemplate> nsfwPromptTemplates;
  final VoiceSettings voiceSettings;
  final VisionSettings visionSettings;
  final bool streaming;
  final bool showAvatars;
  final bool autoScroll;
  final bool debugMode;
  final bool dialogueImmersionEnabled;
  final String trpgDefaultRule;
  final bool trpgAutoSave;
  final bool trpgDiceAnimation;
  final String? trpgDefaultGmProfileId;
  final int trpgGmOutputLength;
  final PresentationMode trpgPresentationMode;
  final PresentationQuality trpgPresentationQuality;
  final bool trpgAutoSpeakGm, trpgAutoSpeakNpc, trpgAutoSpeakNarrator;
  final double trpgMasterVolume,
      trpgBgmVolume,
      trpgAmbientVolume,
      trpgSfxVolume,
      trpgVoiceVolume;
  final int trpgMemoryTokenBudget;

  AppSettings copyWith({
    String? theme,
    double? fontScale,
    String? defaultApiProfileId,
    double? defaultTemperature,
    int? historyMessageCount,
    bool? autoContextCompression,
    int? contextCompressionInterval,
    bool? nsfwEnabled,
    List<NsfwPromptTemplate>? nsfwPromptTemplates,
    VoiceSettings? voiceSettings,
    VisionSettings? visionSettings,
    bool? streaming,
    bool? showAvatars,
    bool? autoScroll,
    bool? debugMode,
    bool? dialogueImmersionEnabled,
    String? trpgDefaultRule,
    bool? trpgAutoSave,
    bool? trpgDiceAnimation,
    String? trpgDefaultGmProfileId,
    int? trpgGmOutputLength,
    PresentationMode? trpgPresentationMode,
    PresentationQuality? trpgPresentationQuality,
    bool? trpgAutoSpeakGm,
    bool? trpgAutoSpeakNpc,
    bool? trpgAutoSpeakNarrator,
    double? trpgMasterVolume,
    double? trpgBgmVolume,
    double? trpgAmbientVolume,
    double? trpgSfxVolume,
    double? trpgVoiceVolume,
    int? trpgMemoryTokenBudget,
  }) => AppSettings(
    theme: theme ?? this.theme,
    fontScale: fontScale ?? this.fontScale,
    defaultApiProfileId: defaultApiProfileId ?? this.defaultApiProfileId,
    defaultTemperature: defaultTemperature ?? this.defaultTemperature,
    historyMessageCount: historyMessageCount ?? this.historyMessageCount,
    autoContextCompression:
        autoContextCompression ?? this.autoContextCompression,
    contextCompressionInterval:
        (contextCompressionInterval ?? this.contextCompressionInterval).clamp(
          2,
          30,
        ),
    nsfwEnabled: nsfwEnabled ?? this.nsfwEnabled,
    nsfwPromptTemplates: nsfwPromptTemplates ?? this.nsfwPromptTemplates,
    voiceSettings: voiceSettings ?? this.voiceSettings,
    visionSettings: visionSettings ?? this.visionSettings,
    streaming: streaming ?? this.streaming,
    showAvatars: showAvatars ?? this.showAvatars,
    autoScroll: autoScroll ?? this.autoScroll,
    debugMode: debugMode ?? this.debugMode,
    dialogueImmersionEnabled:
        dialogueImmersionEnabled ?? this.dialogueImmersionEnabled,
    trpgDefaultRule: trpgDefaultRule ?? this.trpgDefaultRule,
    trpgAutoSave: trpgAutoSave ?? this.trpgAutoSave,
    trpgDiceAnimation: trpgDiceAnimation ?? this.trpgDiceAnimation,
    trpgDefaultGmProfileId:
        trpgDefaultGmProfileId ?? this.trpgDefaultGmProfileId,
    trpgGmOutputLength: (trpgGmOutputLength ?? this.trpgGmOutputLength).clamp(
      500,
      4000,
    ),
    trpgPresentationMode: trpgPresentationMode ?? this.trpgPresentationMode,
    trpgPresentationQuality:
        trpgPresentationQuality ?? this.trpgPresentationQuality,
    trpgAutoSpeakGm: trpgAutoSpeakGm ?? this.trpgAutoSpeakGm,
    trpgAutoSpeakNpc: trpgAutoSpeakNpc ?? this.trpgAutoSpeakNpc,
    trpgAutoSpeakNarrator: trpgAutoSpeakNarrator ?? this.trpgAutoSpeakNarrator,
    trpgMasterVolume: (trpgMasterVolume ?? this.trpgMasterVolume).clamp(0, 1),
    trpgBgmVolume: (trpgBgmVolume ?? this.trpgBgmVolume).clamp(0, 1),
    trpgAmbientVolume: (trpgAmbientVolume ?? this.trpgAmbientVolume).clamp(
      0,
      1,
    ),
    trpgSfxVolume: (trpgSfxVolume ?? this.trpgSfxVolume).clamp(0, 1),
    trpgVoiceVolume: (trpgVoiceVolume ?? this.trpgVoiceVolume).clamp(0, 1),
    trpgMemoryTokenBudget: (trpgMemoryTokenBudget ?? this.trpgMemoryTokenBudget)
        .clamp(500, 12000),
  );

  Map<String, Object?> toJson() => {
    'theme': theme,
    'fontScale': fontScale,
    'defaultApiProfileId': defaultApiProfileId,
    'defaultTemperature': defaultTemperature,
    'historyMessageCount': historyMessageCount,
    'autoContextCompression': autoContextCompression,
    'contextCompressionInterval': contextCompressionInterval,
    'nsfwEnabled': nsfwEnabled,
    'nsfwPromptTemplates': nsfwPromptTemplates
        .map((template) => template.toJson())
        .toList(),
    'voiceSettings': voiceSettings.toJson(),
    'visionSettings': visionSettings.toJson(),
    'streaming': streaming,
    'showAvatars': showAvatars,
    'autoScroll': autoScroll,
    'debugMode': debugMode,
    'dialogueImmersionEnabled': dialogueImmersionEnabled,
    'trpgDefaultRule': trpgDefaultRule,
    'trpgAutoSave': trpgAutoSave,
    'trpgDiceAnimation': trpgDiceAnimation,
    'trpgDefaultGmProfileId': trpgDefaultGmProfileId,
    'trpgGmOutputLength': trpgGmOutputLength,
    'trpgPresentationMode': trpgPresentationMode.name,
    'trpgPresentationQuality': trpgPresentationQuality.name,
    'trpgAutoSpeakGm': trpgAutoSpeakGm,
    'trpgAutoSpeakNpc': trpgAutoSpeakNpc,
    'trpgAutoSpeakNarrator': trpgAutoSpeakNarrator,
    'trpgMasterVolume': trpgMasterVolume,
    'trpgBgmVolume': trpgBgmVolume,
    'trpgAmbientVolume': trpgAmbientVolume,
    'trpgSfxVolume': trpgSfxVolume,
    'trpgVoiceVolume': trpgVoiceVolume,
    'trpgMemoryTokenBudget': trpgMemoryTokenBudget,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    theme: json['theme'] as String? ?? 'dark',
    fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1,
    defaultApiProfileId: json['defaultApiProfileId'] as String?,
    defaultTemperature: (json['defaultTemperature'] as num?)?.toDouble() ?? 0.9,
    historyMessageCount: json['historyMessageCount'] as int? ?? 50,
    autoContextCompression: json['autoContextCompression'] as bool? ?? false,
    contextCompressionInterval:
        (json['contextCompressionInterval'] as int? ?? 6).clamp(2, 30),
    nsfwEnabled: json['nsfwEnabled'] as bool? ?? false,
    nsfwPromptTemplates: _readNsfwTemplates(json['nsfwPromptTemplates']),
    voiceSettings: json['voiceSettings'] is Map
        ? VoiceSettings.fromJson(
            (json['voiceSettings'] as Map).cast<String, Object?>(),
          )
        : const VoiceSettings(),
    visionSettings: json['visionSettings'] is Map
        ? VisionSettings.fromJson(
            (json['visionSettings'] as Map).cast<String, Object?>(),
          )
        : const VisionSettings(),
    streaming: json['streaming'] as bool? ?? true,
    showAvatars: json['showAvatars'] as bool? ?? true,
    autoScroll: json['autoScroll'] as bool? ?? true,
    debugMode: json['debugMode'] as bool? ?? false,
    dialogueImmersionEnabled: json['dialogueImmersionEnabled'] as bool? ?? true,
    trpgDefaultRule: json['trpgDefaultRule'] as String? ?? 'simple_trpg',
    trpgAutoSave: json['trpgAutoSave'] as bool? ?? true,
    trpgDiceAnimation: json['trpgDiceAnimation'] as bool? ?? true,
    trpgDefaultGmProfileId: json['trpgDefaultGmProfileId'] as String?,
    trpgGmOutputLength: ((json['trpgGmOutputLength'] as num?)?.toInt() ?? 2000)
        .clamp(500, 4000),
    trpgPresentationMode: PresentationMode.values.firstWhere(
      (value) => value.name == json['trpgPresentationMode'],
      orElse: () => PresentationMode.immersive,
    ),
    trpgPresentationQuality: PresentationQuality.values.firstWhere(
      (value) => value.name == json['trpgPresentationQuality'],
      orElse: () => PresentationQuality.standard,
    ),
    trpgAutoSpeakGm: json['trpgAutoSpeakGm'] as bool? ?? false,
    trpgAutoSpeakNpc: json['trpgAutoSpeakNpc'] as bool? ?? true,
    trpgAutoSpeakNarrator: json['trpgAutoSpeakNarrator'] as bool? ?? true,
    trpgMasterVolume: ((json['trpgMasterVolume'] as num?)?.toDouble() ?? 1)
        .clamp(0, 1),
    trpgBgmVolume: ((json['trpgBgmVolume'] as num?)?.toDouble() ?? .65).clamp(
      0,
      1,
    ),
    trpgAmbientVolume: ((json['trpgAmbientVolume'] as num?)?.toDouble() ?? .55)
        .clamp(0, 1),
    trpgSfxVolume: ((json['trpgSfxVolume'] as num?)?.toDouble() ?? .85).clamp(
      0,
      1,
    ),
    trpgVoiceVolume: ((json['trpgVoiceVolume'] as num?)?.toDouble() ?? 1).clamp(
      0,
      1,
    ),
    trpgMemoryTokenBudget:
        ((json['trpgMemoryTokenBudget'] as num?)?.toInt() ?? 3000).clamp(
          500,
          12000,
        ),
  );

  static List<NsfwPromptTemplate> _readNsfwTemplates(Object? value) {
    if (value is! List) return defaultNsfwPromptTemplates;
    final parsed = value
        .whereType<Map>()
        .map(
          (item) => NsfwPromptTemplate.fromJson(item.cast<String, Object?>()),
        )
        .where((item) => item.id.isNotEmpty && item.content.trim().isNotEmpty)
        .toList();
    return parsed.isEmpty ? defaultNsfwPromptTemplates : parsed;
  }

  String get activeNsfwPrompt {
    if (!nsfwEnabled) return '';
    return nsfwPromptTemplates
        .where(
          (template) => template.enabled && template.content.trim().isNotEmpty,
        )
        .map((template) => template.content.trim())
        .join('\n\n');
  }
}
