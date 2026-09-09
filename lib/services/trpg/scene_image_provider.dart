abstract interface class SceneImageProvider {
  Future<String?> generateSceneImage({
    required String campaignId,
    required String sceneId,
    required String description,
  });
}

class DisabledSceneImageProvider implements SceneImageProvider {
  const DisabledSceneImageProvider();
  @override
  Future<String?> generateSceneImage({
    required String campaignId,
    required String sceneId,
    required String description,
  }) async => null;
}
