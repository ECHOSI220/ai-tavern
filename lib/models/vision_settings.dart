enum VisionProviderType {
  disabled,
  openAiCompatible,
  gemini,
  ollama;

  String get label => switch (this) {
    disabled => '未启用',
    openAiCompatible => 'OpenAI-Compatible Vision',
    gemini => 'Gemini Vision（预留）',
    ollama => 'Ollama Vision（预留）',
  };
}

class VisionSettings {
  const VisionSettings({
    this.enabled = false,
    this.provider = VisionProviderType.openAiCompatible,
    this.baseUrl = '',
    this.model = '',
    this.ocrEnabled = true,
    this.maxImages = 3,
    this.maxImageDimension = 1600,
    this.maxImageBytes = 10 * 1024 * 1024,
    this.timeoutSeconds = 45,
    this.debugMode = false,
  });

  final bool enabled;
  final VisionProviderType provider;
  final String baseUrl;
  final String model;
  final bool ocrEnabled;
  final int maxImages;
  final int maxImageDimension;
  final int maxImageBytes;
  final int timeoutSeconds;
  final bool debugMode;

  VisionSettings copyWith({
    bool? enabled,
    VisionProviderType? provider,
    String? baseUrl,
    String? model,
    bool? ocrEnabled,
    int? maxImages,
    int? maxImageDimension,
    int? maxImageBytes,
    int? timeoutSeconds,
    bool? debugMode,
  }) => VisionSettings(
    enabled: enabled ?? this.enabled,
    provider: provider ?? this.provider,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    ocrEnabled: ocrEnabled ?? this.ocrEnabled,
    maxImages: (maxImages ?? this.maxImages).clamp(1, 3),
    maxImageDimension: (maxImageDimension ?? this.maxImageDimension).clamp(
      720,
      2560,
    ),
    maxImageBytes: (maxImageBytes ?? this.maxImageBytes).clamp(
      1024 * 1024,
      10 * 1024 * 1024,
    ),
    timeoutSeconds: (timeoutSeconds ?? this.timeoutSeconds).clamp(15, 120),
    debugMode: debugMode ?? this.debugMode,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'provider': provider.name,
    'baseUrl': baseUrl,
    'model': model,
    'ocrEnabled': ocrEnabled,
    'maxImages': maxImages,
    'maxImageDimension': maxImageDimension,
    'maxImageBytes': maxImageBytes,
    'timeoutSeconds': timeoutSeconds,
    'debugMode': debugMode,
  };

  factory VisionSettings.fromJson(Map<String, Object?> json) => VisionSettings(
    enabled: json['enabled'] as bool? ?? false,
    provider:
        VisionProviderType.values
            .where((item) => item.name == json['provider'])
            .firstOrNull ??
        VisionProviderType.openAiCompatible,
    baseUrl: json['baseUrl'] as String? ?? '',
    model: json['model'] as String? ?? '',
    ocrEnabled: json['ocrEnabled'] as bool? ?? true,
    maxImages: (json['maxImages'] as int? ?? 3).clamp(1, 3),
    maxImageDimension: (json['maxImageDimension'] as int? ?? 1600).clamp(
      720,
      2560,
    ),
    maxImageBytes: (json['maxImageBytes'] as int? ?? 10 * 1024 * 1024).clamp(
      1024 * 1024,
      10 * 1024 * 1024,
    ),
    timeoutSeconds: (json['timeoutSeconds'] as int? ?? 45).clamp(15, 120),
    debugMode: json['debugMode'] as bool? ?? false,
  );
}
