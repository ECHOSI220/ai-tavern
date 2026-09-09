class LoreEntry {
  const LoreEntry({
    required this.id,
    required this.title,
    this.keywords = const [],
    this.content = '',
    this.alwaysActive = false,
    this.enabled = true,
    this.priority = 0,
  });

  final String id;
  final String title;
  final List<String> keywords;
  final String content;
  final bool alwaysActive;
  final bool enabled;
  final int priority;

  LoreEntry copyWith({
    String? id,
    String? title,
    List<String>? keywords,
    String? content,
    bool? alwaysActive,
    bool? enabled,
    int? priority,
  }) => LoreEntry(
    id: id ?? this.id,
    title: title ?? this.title,
    keywords: keywords ?? this.keywords,
    content: content ?? this.content,
    alwaysActive: alwaysActive ?? this.alwaysActive,
    enabled: enabled ?? this.enabled,
    priority: priority ?? this.priority,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'keywords': keywords,
    'content': content,
    'alwaysActive': alwaysActive,
    'enabled': enabled,
    'priority': priority,
  };

  factory LoreEntry.fromJson(Map<String, Object?> json) => LoreEntry(
    id: json['id']! as String,
    title: json['title']! as String,
    keywords: (json['keywords'] as List<Object?>? ?? const []).cast<String>(),
    content: json['content'] as String? ?? '',
    alwaysActive: json['alwaysActive'] as bool? ?? false,
    enabled: json['enabled'] as bool? ?? true,
    priority: json['priority'] as int? ?? 0,
  );
}
