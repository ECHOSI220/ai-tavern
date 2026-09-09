import 'chat_attachment.dart';

enum ChatRole { system, user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.saveId,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.branchId = 'main',
    this.parentMessageId,
    this.generationIndex = 0,
    this.isInterrupted = false,
    this.errorMessage,
    this.attachments = const [],
    this.visionContext,
  });

  final String id;
  final String saveId;
  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String branchId;
  final String? parentMessageId;
  final int generationIndex;
  final bool isInterrupted;
  final String? errorMessage;
  final List<ChatAttachment> attachments;
  final String? visionContext;

  bool get hasImages => attachments.any(
    (attachment) => attachment.type == ChatAttachmentType.image,
  );

  bool get hasModelContent =>
      content.trim().isNotEmpty || (visionContext?.trim().isNotEmpty ?? false);

  String get modelContent {
    final visual = visionContext?.trim() ?? '';
    // VisionContextFormatter 已把原始用户文字放进隐藏上下文，避免重复注入。
    return visual.isNotEmpty ? visual : content.trim();
  }

  ChatMessage copyWith({
    String? id,
    String? saveId,
    ChatRole? role,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? branchId,
    String? parentMessageId,
    int? generationIndex,
    bool? isInterrupted,
    String? errorMessage,
    List<ChatAttachment>? attachments,
    String? visionContext,
    bool clearVisionContext = false,
  }) => ChatMessage(
    id: id ?? this.id,
    saveId: saveId ?? this.saveId,
    role: role ?? this.role,
    content: content ?? this.content,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    branchId: branchId ?? this.branchId,
    parentMessageId: parentMessageId ?? this.parentMessageId,
    generationIndex: generationIndex ?? this.generationIndex,
    isInterrupted: isInterrupted ?? this.isInterrupted,
    errorMessage: errorMessage ?? this.errorMessage,
    attachments: attachments ?? this.attachments,
    visionContext: clearVisionContext
        ? null
        : visionContext ?? this.visionContext,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'saveId': saveId,
    'role': role.name,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'branchId': branchId,
    'parentMessageId': parentMessageId,
    'generationIndex': generationIndex,
    'isInterrupted': isInterrupted,
    'errorMessage': errorMessage,
    'attachments': attachments.map((item) => item.toJson()).toList(),
    'visionContext': visionContext,
  };

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
    id: json['id']! as String,
    saveId: json['saveId']! as String,
    role: ChatRole.values.byName(json['role']! as String),
    content: json['content']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    branchId: json['branchId'] as String? ?? 'main',
    parentMessageId: json['parentMessageId'] as String?,
    generationIndex: json['generationIndex'] as int? ?? 0,
    isInterrupted: json['isInterrupted'] as bool? ?? false,
    errorMessage: json['errorMessage'] as String?,
    attachments: (json['attachments'] as List<Object?>? ?? const [])
        .whereType<Map>()
        .map((item) => ChatAttachment.fromJson(item.cast<String, Object?>()))
        .toList(),
    visionContext: json['visionContext'] as String?,
  );
}
