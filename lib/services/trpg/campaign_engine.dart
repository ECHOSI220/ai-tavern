import '../../models/campaign_models.dart';
import '../../models/trpg_models.dart';

class CampaignEngineResult {
  const CampaignEngineResult({
    required this.session,
    required this.triggeredIds,
  });
  final TRPGSession session;
  final List<String> triggeredIds;
}

class CampaignEngine {
  const CampaignEngine();

  CampaignEngineResult evaluate(
    TRPGSession session,
    CampaignDocument campaign,
  ) {
    var next = session;
    final fired = <String>[];
    final triggers = campaign.acts
        .expand((act) => act.chapters)
        .expand((chapter) => chapter.storyNodes)
        .expand((node) => node.triggers);
    for (final trigger in triggers) {
      if (next.campaignState.triggeredEvents.contains(trigger.id)) continue;
      if (!_matches(trigger, next)) continue;
      next = _applyEffects(next, trigger.effects);
      fired.add(trigger.id);
    }
    if (fired.isNotEmpty) {
      next = next.copyWith(
        campaignState: next.campaignState.copyWith(
          triggeredEvents: [...next.campaignState.triggeredEvents, ...fired],
        ),
      );
    }
    return CampaignEngineResult(session: next, triggeredIds: fired);
  }

  bool _matches(CampaignTrigger trigger, TRPGSession session) {
    final Object? actual = switch (trigger.conditionType) {
      'flag' =>
        session.campaignState.flags[trigger.key] ??
            session.worldState.worldFlags[trigger.key],
      'item' => session.playerCharacters.any(
        (character) =>
            character.inventory.contains(trigger.key) ||
            character.inventoryItems.any((item) => item.id == trigger.key),
      ),
      'clue' => session.campaignState.clues.any(
        (clue) => clue.clueId == trigger.key && clue.discovered,
      ),
      'location' => session.campaignState.currentLocationId,
      _ => session.campaignState.variables[trigger.key],
    };
    return switch (trigger.operator) {
      'notEquals' => actual != trigger.value,
      'greaterThan' =>
        actual is num &&
            trigger.value is num &&
            actual > (trigger.value as num),
      'contains' => actual is Iterable && actual.contains(trigger.value),
      _ => actual == trigger.value,
    };
  }

  TRPGSession _applyEffects(
    TRPGSession session,
    List<Map<String, Object?>> effects,
  ) {
    var next = session;
    for (final effect in effects) {
      switch (effect['type']) {
        case 'setFlag':
          final key = effect['key']?.toString();
          if (key != null) {
            next = next.copyWith(
              campaignState: next.campaignState.copyWith(
                flags: {
                  ...next.campaignState.flags,
                  key: effect['value'] as bool? ?? true,
                },
              ),
            );
          }
        case 'discoverLocation':
          final id = effect['locationId']?.toString();
          if (id != null) {
            next = next.copyWith(
              campaignState: next.campaignState.copyWith(
                discoveredLocations: {
                  ...next.campaignState.discoveredLocations,
                  id,
                }.toList(),
              ),
            );
          }
        case 'activateQuest':
          final id = effect['questId']?.toString();
          if (id != null) {
            next = next.copyWith(
              campaignState: next.campaignState.copyWith(
                activeQuests: {...next.campaignState.activeQuests, id}.toList(),
              ),
            );
          }
      }
    }
    return next;
  }
}
