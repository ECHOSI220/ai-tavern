import '../../models/chat_attachment.dart';
import '../../models/vision_analysis.dart';
import '../../models/vision_settings.dart';

class VisionException implements Exception {
  const VisionException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null ? message : '$statusCode: $message';
}

abstract interface class VisionProvider {
  Future<void> initialize();
  Future<bool> isAvailable();

  Future<VisionAnalysis> analyzeImage(
    ChatAttachment image, {
    required String userQuestion,
  });

  Future<List<VisionAnalysis>> analyzeImages(
    List<ChatAttachment> images, {
    required String userQuestion,
  });

  Future<String> testConnection();
  void dispose();
}

class DisabledVisionProvider implements VisionProvider {
  const DisabledVisionProvider();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<VisionAnalysis> analyzeImage(
    ChatAttachment image, {
    required String userQuestion,
  }) => throw const VisionException('尚未启用或配置看图能力');

  @override
  Future<List<VisionAnalysis>> analyzeImages(
    List<ChatAttachment> images, {
    required String userQuestion,
  }) => throw const VisionException('尚未启用或配置看图能力');

  @override
  Future<String> testConnection() => throw const VisionException('尚未启用或配置看图能力');

  @override
  void dispose() {}
}

VisionProvider unsupportedVisionProvider(VisionSettings settings) =>
    throw VisionException('${settings.provider.label} 当前仅作为扩展位预留');
