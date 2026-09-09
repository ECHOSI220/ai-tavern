class ApiProfile {
  const ApiProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    this.apiType = 'openai-compatible',
    this.temperature = 0.9,
    this.topP = 1,
    this.maxTokens = 2000,
    this.stream = true,
    this.timeoutSeconds = 60,
    this.extraHeaders = const {},
  });

  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final String apiType;
  final double temperature;
  final double topP;
  final int maxTokens;
  final bool stream;
  final int timeoutSeconds;
  final Map<String, String> extraHeaders;

  ApiProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? model,
    String? apiType,
    double? temperature,
    double? topP,
    int? maxTokens,
    bool? stream,
    int? timeoutSeconds,
    Map<String, String>? extraHeaders,
  }) => ApiProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    apiType: apiType ?? this.apiType,
    temperature: temperature ?? this.temperature,
    topP: topP ?? this.topP,
    maxTokens: maxTokens ?? this.maxTokens,
    stream: stream ?? this.stream,
    timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    extraHeaders: extraHeaders ?? this.extraHeaders,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'model': model,
    'apiType': apiType,
    'temperature': temperature,
    'topP': topP,
    'maxTokens': maxTokens,
    'stream': stream,
    'timeoutSeconds': timeoutSeconds,
    'extraHeaders': extraHeaders,
  };

  factory ApiProfile.fromJson(Map<String, Object?> json) => ApiProfile(
    id: json['id']! as String,
    name: json['name']! as String,
    baseUrl: json['baseUrl']! as String,
    model: json['model']! as String,
    apiType: json['apiType'] as String? ?? 'openai-compatible',
    temperature: (json['temperature'] as num?)?.toDouble() ?? 0.9,
    topP: (json['topP'] as num?)?.toDouble() ?? 1,
    maxTokens: json['maxTokens'] as int? ?? 2000,
    stream: json['stream'] as bool? ?? true,
    timeoutSeconds: json['timeoutSeconds'] as int? ?? 60,
    extraHeaders: Map<String, String>.from(
      json['extraHeaders'] as Map<Object?, Object?>? ?? const {},
    ),
  );
}
