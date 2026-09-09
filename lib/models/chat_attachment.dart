import 'vision_analysis.dart';

enum ChatAttachmentType { image }

enum AttachmentAnalysisStatus { pending, analyzing, analyzed, error }

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.localPath,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.sizeBytes,
    this.type = ChatAttachmentType.image,
    this.analysisStatus = AttachmentAnalysisStatus.pending,
    this.analysis,
    this.errorMessage,
  });

  final String id;
  final ChatAttachmentType type;
  final String localPath;
  final String mimeType;
  final int width;
  final int height;
  final int sizeBytes;
  final AttachmentAnalysisStatus analysisStatus;
  final VisionAnalysis? analysis;
  final String? errorMessage;

  ChatAttachment copyWith({
    String? localPath,
    String? mimeType,
    int? width,
    int? height,
    int? sizeBytes,
    AttachmentAnalysisStatus? analysisStatus,
    VisionAnalysis? analysis,
    String? errorMessage,
    bool clearError = false,
  }) => ChatAttachment(
    id: id,
    type: type,
    localPath: localPath ?? this.localPath,
    mimeType: mimeType ?? this.mimeType,
    width: width ?? this.width,
    height: height ?? this.height,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    analysisStatus: analysisStatus ?? this.analysisStatus,
    analysis: analysis ?? this.analysis,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'localPath': localPath,
    'mimeType': mimeType,
    'width': width,
    'height': height,
    'sizeBytes': sizeBytes,
    'analysisStatus': analysisStatus.name,
    if (analysis != null) 'analysis': analysis!.toJson(),
    'errorMessage': errorMessage,
  };

  factory ChatAttachment.fromJson(Map<String, Object?> json) => ChatAttachment(
    id: json['id']! as String,
    type:
        ChatAttachmentType.values
            .where((item) => item.name == json['type'])
            .firstOrNull ??
        ChatAttachmentType.image,
    localPath: json['localPath'] as String? ?? '',
    mimeType: json['mimeType'] as String? ?? 'image/jpeg',
    width: json['width'] as int? ?? 0,
    height: json['height'] as int? ?? 0,
    sizeBytes: json['sizeBytes'] as int? ?? 0,
    analysisStatus:
        AttachmentAnalysisStatus.values
            .where((item) => item.name == json['analysisStatus'])
            .firstOrNull ??
        AttachmentAnalysisStatus.pending,
    analysis: json['analysis'] is Map
        ? VisionAnalysis.fromJson(
            (json['analysis'] as Map).cast<String, Object?>(),
          )
        : null,
    errorMessage: json['errorMessage'] as String?,
  );
}
