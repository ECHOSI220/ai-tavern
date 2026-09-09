import '../../models/social_models.dart';

/// Provider-neutral seam for a future Android/iOS push implementation.
/// Phase 7 always stores notifications in the authoritative backend; this
/// interface deliberately carries no API keys or device-local model secrets.
abstract interface class CampaignNotificationDispatcher {
  Future<void> dispatch(CampaignNotification notification);
}

class NoopCampaignNotificationDispatcher
    implements CampaignNotificationDispatcher {
  const NoopCampaignNotificationDispatcher();

  @override
  Future<void> dispatch(CampaignNotification notification) async {}
}
