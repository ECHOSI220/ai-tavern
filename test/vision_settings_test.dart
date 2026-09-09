import 'package:ai_tavern/models/app_settings.dart';
import 'package:ai_tavern/models/vision_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('旧设置默认关闭看图能力', () {
    final restored = AppSettings.fromJson(const {});

    expect(restored.visionSettings.enabled, isFalse);
    expect(
      restored.visionSettings.provider,
      VisionProviderType.openAiCompatible,
    );
  });

  test('视觉设置 JSON 往返且限制图片数量', () {
    final settings = const VisionSettings(
      enabled: true,
      baseUrl: 'https://vision.example/v1',
      model: 'vision-model',
      maxImages: 2,
      debugMode: true,
    );

    final restored = VisionSettings.fromJson(settings.toJson());

    expect(restored.enabled, isTrue);
    expect(restored.baseUrl, 'https://vision.example/v1');
    expect(restored.maxImages, 2);
    expect(restored.debugMode, isTrue);
    expect(settings.copyWith(maxImages: 99).maxImages, 3);
  });
}
