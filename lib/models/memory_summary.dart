class MemorySummary {
  const MemorySummary({
    this.content = '',
    required this.updatedAt,
    this.coveredMessageId,
  });

  final String content;
  final DateTime updatedAt;
  final String? coveredMessageId;

  MemorySummary copyWith({
    String? content,
    DateTime? updatedAt,
    String? coveredMessageId,
    bool clearCoveredMessageId = false,
  }) => MemorySummary(
    content: content ?? this.content,
    updatedAt: updatedAt ?? this.updatedAt,
    coveredMessageId: clearCoveredMessageId
        ? null
        : coveredMessageId ?? this.coveredMessageId,
  );

  Map<String, Object?> toJson() => {
    'content': content,
    'updatedAt': updatedAt.toIso8601String(),
    'coveredMessageId': coveredMessageId,
  };

  factory MemorySummary.fromJson(Map<String, Object?> json) => MemorySummary(
    content: json['content'] as String? ?? '',
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    coveredMessageId: json['coveredMessageId'] as String?,
  );
}
