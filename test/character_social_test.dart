import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tavern/models/character.dart';
import 'package:ai_tavern/models/character_social.dart';
import 'package:ai_tavern/services/character_social/social_engine.dart';
import 'package:ai_tavern/repositories/character_social_repository.dart';
import 'package:ai_tavern/services/storage_service.dart';

void main() {
  test('quiet characters stay less active than outgoing characters', () {
    final quiet = SocialProfileInferencer.infer(
      const Character(id: 'a', name: 'A', personality: '沉默寡言，不善社交'),
    );
    final outgoing = SocialProfileInferencer.infer(
      const Character(id: 'b', name: 'B', personality: '活泼外向，健谈'),
    );
    expect(quiet.postFrequency, lessThan(1));
    expect(outgoing.postFrequency, greaterThan(quiet.postFrequency));
    expect(quiet.initiative, lessThan(outgoing.initiative));
  });
  test('private memories never enter other characters or groups', () {
    final m = SocialRecord.create('memory', {
      'content': '秘密',
      'knownBy': ['user', 'a'],
    }, worldId: 'fate');
    expect(
      SocialVisibilityFilter.allows(m, viewer: 'a', worldId: 'fate'),
      isTrue,
    );
    expect(
      SocialVisibilityFilter.allows(m, viewer: 'b', worldId: 'fate'),
      isFalse,
    );
    expect(
      SocialVisibilityFilter.allows(m, viewer: 'a', worldId: 'nikke'),
      isFalse,
    );
    expect(
      SocialVisibilityFilter.allows(
        m,
        viewer: 'a',
        worldId: 'fate',
        participants: ['a', 'b'],
      ),
      isFalse,
    );
  });
  test('post audience enforced and unknown visibility fails closed', () {
    final p = SocialRecord.create('post', {
      'visibility': 'SELECTED_CHARACTERS',
      'audience': ['a'],
    });
    expect(
      SocialVisibilityFilter.allows(p, viewer: 'a', worldId: 'default'),
      isTrue,
    );
    expect(
      SocialVisibilityFilter.allows(p, viewer: 'b', worldId: 'default'),
      isFalse,
    );
    expect(
      SocialVisibilityFilter.allows(
        p.change({'visibility': 'unknown'}),
        viewer: 'a',
        worldId: 'default',
      ),
      isFalse,
    );
  });
  test('memory extraction requires verbatim evidence', () {
    final records = SocialMemoryExtractor.validate([
      {'content': '用户答应明天来', 'evidence': '我明天会来', 'importance': 8},
      {'content': '用户住在上海', 'evidence': '我住上海', 'importance': 8},
      {'content': '普通招呼', 'evidence': '晚上好', 'importance': 1},
    ], '晚上好，我明天会来');
    expect(records, hasLength(1));
  });
  test('relationships bounded and never auto-label romance', () {
    var r = <String, Object?>{};
    for (var i = 0; i < 100; i++) {
      r = SocialRelationshipState.apply(r, {
        'trust': 10000,
        'closeness': 10000,
      });
    }
    expect(r['trust'], 100);
    expect(SocialRelationshipState.label(r), isNot(contains('恋')));
    final conflict = SocialRelationshipState.apply(r, {
      'trust': -3,
      'tension': 3,
    });
    expect(conflict['trust'], 97);
    expect(conflict['tension'], 3);
  });
  test('mood transition is gradual; schedule determines sleeping', () {
    final next = MoodTransitionResolver.resolve({'valence': 10}, 'conflict');
    expect(next['valence'], 2);
    final schedule = CharacterSchedule.at(
      const Character(id: 'a', name: 'A'),
      const CharacterSocialProfile(),
      DateTime(2026, 9, 12, 2),
    );
    expect(schedule['status'], '请勿打扰');
  });
  group('local replica', () {
    late StorageService storage;
    late CharacterSocialRepository a, b;
    setUp(() async {
      storage = StorageService();
      await storage.initialize(databasePath: ':memory:');
      a = CharacterSocialRepository(storage, owner: 'a');
      b = CharacterSocialRepository(storage, owner: 'b');
      await a.initialize();
    });
    tearDown(() async {
      await storage.database.close();
    });
    test('account isolation, paging and tombstones', () async {
      for (var i = 0; i < 12; i++) {
        await a.save(
          SocialRecord.create('message', {'content': '$i'}, parentId: 'chat'),
        );
      }
      expect(await a.list('message', limit: 5), hasLength(5));
      expect(await b.list('message'), isEmpty);
      final first = (await a.list('message')).first;
      await a.save(first.change({}, deleted: true));
      expect(await a.list('message'), hasLength(11));
    });
    test('stale transaction rolls back event and state', () async {
      final contact = SocialRecord.create('contact', {});
      await a.save(contact);
      await a.save(contact.change({'x': 1}));
      final event = SocialRecord.create('event', {});
      await expectLater(
        a.saveAll([
          event,
          contact.change({'x': 2}),
        ]),
        throwsStateError,
      );
      expect(await a.get(event.id), isNull);
      expect((await a.get(contact.id))!.number('x'), 1);
    });
    test(
      'cloud conflict preserves both variants, explicit resolution works',
      () async {
        final record = SocialRecord.create('contact', {'remark': 'local'});
        await a.save(record);
        final remote = {
          ...record.toCloud(),
          'payload': {'remark': 'remote'},
          'version': 2,
        };
        await a.acceptRemote(remote);
        final conflict = (await a.conflicts()).single;
        expect(conflict.text('remark'), 'local');
        expect(conflict.conflict?['payload'], {'remark': 'remote'});
        await a.resolveConflict(conflict, keepLocal: false);
        expect((await a.get(record.id))!.text('remark'), 'remote');
      },
    );
    test(
      'sync acknowledges exact sent revision without dropping new edits',
      () async {
        final record = SocialRecord.create('contact', {'remark': 'first'});
        await a.save(record);
        await a.save(record.change({'remark': 'second'}));
        await a.acceptRemote({...record.toCloud(), 'version': 1}, sent: record);
        final current = (await a.get(record.id))!;
        expect(current.dirty, isTrue);
        expect(current.text('remark'), 'second');
        expect(current.baseVersion, 1);
      },
    );
    test('pending upload does not split local atomic batches', () async {
      await a.saveAll([
        SocialRecord.create('event', {}),
        SocialRecord.create('post', {}),
      ]);
      await a.save(SocialRecord.create('settings', {}));
      expect(await a.pending(), hasLength(2));
    });
  });
}
