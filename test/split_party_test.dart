import 'package:ai_tavern/models/trpg_party_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('party groups split, merge, and keep stable ids', () {
    const manager = PartyGroupManager();
    final first = {
      'a': const CharacterLocationState(characterId: 'a', locationId: 'hall'),
      'b': const CharacterLocationState(characterId: 'b', locationId: 'hall'),
      'c': const CharacterLocationState(characterId: 'c', locationId: 'hall'),
    };
    final initial = manager.rebuild(first);
    expect(initial, hasLength(1));
    final hallId = initial.single.groupId;
    final split = manager.rebuild({
      'a': first['a']!.copyWith(locationId: 'left'),
      'b': first['b']!.copyWith(locationId: 'right'),
      'c': first['c']!,
    }, previous: initial);
    expect(split, hasLength(3));
    expect(
      split.firstWhere((group) => group.locationId == 'hall').groupId,
      isNot(hallId),
    );
    final stable = manager.rebuild({
      'a': first['a']!.copyWith(locationId: 'left'),
      'b': first['b']!.copyWith(locationId: 'right'),
      'c': first['c']!,
    }, previous: split);
    expect(
      stable.map((group) => group.groupId),
      containsAll(split.map((group) => group.groupId)),
    );
    final merged = manager.rebuild({
      'a': first['a']!,
      'b': first['b']!,
      'c': first['c']!,
    }, previous: split);
    expect(merged, hasLength(1));
    expect(merged.single.characterIds, containsAll(['a', 'b', 'c']));
  });

  test('location state round trips without sharing knowledge fields', () {
    final state = CharacterLocationState(
      characterId: 'a',
      sceneId: 'hospital',
      locationId: 'basement',
      metadata: const {
        'privateKnowledge': ['key'],
      },
    );
    final restored = CharacterLocationState.fromJson(state.toJson());
    expect(restored.locationId, 'basement');
    expect(restored.metadata['privateKnowledge'], ['key']);
  });
}
