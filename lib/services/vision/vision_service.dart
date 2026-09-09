import '../../models/chat_attachment.dart';
import '../../models/vision_analysis.dart';
import '../../models/vision_settings.dart';
import 'openai_compatible_vision_provider.dart';
import 'vision_provider.dart';

class VisionService {
  VisionService({VisionProvider Function(VisionSettings, String)? factory})
    : _factory = factory ?? _defaultFactory;

  final VisionProvider Function(VisionSettings, String) _factory;
  VisionProvider? _activeProvider;

  Future<List<VisionAnalysis>> analyzeImages({
    required VisionSettings settings,
    required String apiKey,
    required List<ChatAttachment> images,
    required String userQuestion,
  }) async {
    if (!settings.enabled || settings.provider == VisionProviderType.disabled) {
      throw const VisionException('看图能力尚未启用');
    }
    final provider = _factory(settings, apiKey);
    _activeProvider = provider;
    try {
      await provider.initialize();
      return await provider.analyzeImages(images, userQuestion: userQuestion);
    } finally {
      provider.dispose();
      if (identical(_activeProvider, provider)) _activeProvider = null;
    }
  }

  Future<String> testConnection({
    required VisionSettings settings,
    required String apiKey,
  }) async {
    final provider = _factory(settings, apiKey);
    try {
      await provider.initialize();
      return await provider.testConnection();
    } finally {
      provider.dispose();
    }
  }

  void cancel() {
    _activeProvider?.dispose();
    _activeProvider = null;
  }

  static VisionProvider _defaultFactory(
    VisionSettings settings,
    String apiKey,
  ) => switch (settings.provider) {
    VisionProviderType.disabled => const DisabledVisionProvider(),
    VisionProviderType.openAiCompatible => OpenAiCompatibleVisionProvider(
      settings: settings,
      apiKey: apiKey,
    ),
    VisionProviderType.gemini ||
    VisionProviderType.ollama => unsupportedVisionProvider(settings),
  };
}
