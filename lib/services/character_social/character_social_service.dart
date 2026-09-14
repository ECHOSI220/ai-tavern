import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../models/character.dart';
import '../../models/character_social.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../repositories/character_social_repository.dart';
import '../../repositories/settings_repository.dart';
import '../ai_service.dart';
import 'social_engine.dart';
import 'social_avatar_codec.dart';

class SocialBudgetExhausted implements Exception {
  @override
  String toString() => '今日自动模拟预算已用完，改用规则推进';
}

class CharacterSocialService {
  CharacterSocialService({
    required this.repository,
    required this.cards,
    required this.api,
    required this.settings,
    this.reserveCloudCall,
    AiService? ai,
  }) : ai = ai ?? AiService();
  final CharacterSocialRepository repository;
  final CharacterCardRepository cards;
  final ApiRepository api;
  final SettingsRepository settings;
  final AiService ai;
  final Future<void> Function(int limit)? reserveCloudCall;
  bool _catchingUp = false;
  final _generating = <String>{};
  Future<void> _providerTail = Future<void>.value();
  bool _disposed = false;
  Future<void> _memoryTail = Future<void>.value();
  Future<void> get pendingMemory => _memoryTail;
  void dispose() {
    _disposed = true;
    ai.cancel();
  }

  String stable(String value) => const Uuid().v5(Namespace.url.value, value);

  Future<SocialRecord> preferences() async =>
      await repository.get('settings') ??
      SocialRecord.create('settings', {
        'autoLife': true,
        'autoMoments': true,
        'proactive': false,
        'quality': 'lowCost',
        'instantReply': true,
        'dailyBudget': 12,
        'sharedMemory': false,
        'quietHours': true,
        'notifications': 'important',
      }, id: 'settings');
  Future<void> configure(SocialData patch) async {
    final old = await repository.get('settings');
    await repository.save(
      old == null
          ? SocialRecord.create('settings', {
              ...(await preferences()).data,
              ...patch,
            }, id: 'settings')
          : old.change(patch),
    );
  }

  Future<void> initialize() async {
    await repository.initialize();
    if (await repository.get('default') == null) {
      await repository.save(
        SocialRecord.create('world', {
          'name': '默认社交世界',
          'timeMode': 'realTime',
          'publicLore': '',
        }, id: 'default'),
      );
    }
  }

  Future<SocialRecord> addCharacter(
    Character card, {
    String worldId = 'default',
  }) async {
    await initialize();
    // Imported NPCs/current-save characters become genuine reusable cards first.
    await cards.upsert(card);
    final id = stable('contact:$worldId:${card.id}');
    final existing = await repository.get(id);
    if (existing != null && !existing.deleted) return existing;
    final profile = SocialProfileInferencer.infer(card);
    final data = <String, Object?>{
      'profile': profile.toJson(),
      'relationship': SocialRelationshipState.apply({}, {}),
      'mood': MoodTransitionResolver.resolve({}, 'daily'),
      'schedule': CharacterSchedule.at(card, profile, DateTime.now()),
      'lastSimulated': DateTime.now().millisecondsSinceEpoch,
      'remark': '',
      'enabled': true,
    };
    final contact =
        existing?.change(data, deleted: false) ??
        SocialRecord.create(
          'contact',
          data,
          id: id,
          worldId: worldId,
          characterId: card.id,
        );
    final conversationId = stable('dm:$id');
    final writes = <SocialRecord>[contact];
    if (await repository.get(conversationId) == null) {
      writes.add(
        SocialRecord.create(
          'conversation',
          {
            'members': [card.id],
            'contactId': id,
            'group': false,
          },
          id: conversationId,
          worldId: worldId,
          characterId: card.id,
        ),
      );
    }
    // One separate card mirror per card supports cross-device restore, not a second persona in contacts.
    final mirror = await repository.get(stable('card:${card.id}'));
    writes.add(
      mirror == null
          ? SocialRecord.create(
              'card',
              await SocialAvatarCodec.encode(card),
              id: stable('card:${card.id}'),
              characterId: card.id,
            )
          : mirror.change(await SocialAvatarCodec.encode(card)),
    );
    await repository.saveAll(writes);
    return contact;
  }

  Future<Character?> character(String id) async {
    final live = (await cards.getAll()).where((c) => c.id == id).firstOrNull;
    if (live != null) return live;
    final backup = await repository.get(stable('card:$id'));
    return backup == null || backup.deleted
        ? null
        : Character.fromJson(backup.data);
  }

  Future<SocialRecord?> contactFor(String characterId, String worldId) =>
      repository.get(stable('contact:$worldId:$characterId'));
  Future<SocialRecord> createGroup(
    String name,
    List<SocialRecord> contacts,
  ) async {
    if (contacts.length < 2 ||
        contacts.length > 8 ||
        contacts.map((v) => v.worldId).toSet().length != 1) {
      throw StateError('请选择同一世界的 2–8 位联系人');
    }
    final group = SocialRecord.create('conversation', {
      'name': name,
      'members': contacts.map((c) => c.characterId).toList(),
      'group': true,
    }, worldId: contacts.first.worldId);
    final writes = <SocialRecord>[group];
    for (var a = 0; a < contacts.length; a++) {
      for (var b = a + 1; b < contacts.length; b++) {
        final pair = [contacts[a].characterId, contacts[b].characterId]..sort();
        final id = stable('edge:${group.worldId}:${pair.join(':')}');
        if (await repository.get(id) == null) {
          writes.add(
            SocialRecord.create(
              'edge',
              {'members': pair, 'reason': '用户介绍进同一个群聊', 'relation': '初识'},
              id: id,
              worldId: group.worldId,
            ),
          );
        }
      }
    }
    await repository.saveAll(writes);
    return group;
  }

  Future<void> _reserveAutomaticCall() async {
    final prefs = await preferences();
    final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final id = 'budget:$day';
    final budget = await repository.get(id);
    final count = budget?.number('count') ?? 0;
    if (count >= prefs.number('dailyBudget', 12)) {
      throw SocialBudgetExhausted();
    }
    try {
      await reserveCloudCall?.call(prefs.number('dailyBudget', 12));
    } catch (e) {
      if (e.toString().contains('Automatic AI budget exhausted')) {
        throw SocialBudgetExhausted();
      }
      rethrow;
    }
    await repository.save(
      budget == null
          ? SocialRecord.create('budget', {'count': 1}, id: id)
          : budget.change({'count': count + 1}),
    );
  }

  Future<String> generate(
    List<Map<String, String>> messages, {
    bool automatic = false,
    void Function(String)? onChunk,
  }) async {
    // AiService owns one active stream. Queue social requests so foreground
    // chat and background moments cannot cancel each other's network call.
    final previous = _providerTail;
    final completed = Completer<void>();
    _providerTail = completed.future;
    await previous;
    try {
      if (_disposed) throw StateError('角色社交已关闭，请重新进入后重试');
      return await _generateOnce(
        messages,
        automatic: automatic,
        onChunk: onChunk,
      );
    } finally {
      completed.complete();
    }
  }

  Future<String> _generateOnce(
    List<Map<String, String>> messages, {
    bool automatic = false,
    void Function(String)? onChunk,
  }) async {
    if (automatic) await _reserveAutomaticCall();
    final config = await settings.load();
    final profiles = await api.getAll();
    final profile =
        profiles.where((p) => p.id == config.defaultApiProfileId).firstOrNull ??
        profiles.firstOrNull;
    if (profile == null) throw StateError('请先在应用设置中配置 AI 模型');
    final key = await api.readApiKey(profile.id);
    if (key.trim().isEmpty) throw StateError('所选模型没有 API 密钥');
    var result = '';
    try {
      await for (final chunk
          in ai
              .streamChat(profile: profile, apiKey: key, messages: messages)
              .timeout(const Duration(seconds: 120))) {
        result += chunk;
        if (result.length > 16000) {
          ai.cancel();
          throw StateError('模型回复超出长度限制');
        }
        onChunk?.call(result);
      }
      if (_disposed) throw StateError('回复已取消，用户消息已保留');
      if (result.trim().isEmpty) throw StateError('模型返回了空内容，请重试');
      return result.trim();
    } on TimeoutException {
      ai.cancel();
      throw StateError('模型回复超时，请重试');
    }
  }

  Object? parseJson(String text) => jsonDecode(
    text.replaceAll(RegExp(r'^```(?:json)?\s*|\s*```$'), '').trim(),
  );

  Future<List<String>> _speakers(
    SocialRecord conversation,
    List<SocialRecord> history,
  ) async {
    final members = conversation.strings('members');
    if (!conversation.flag('group')) return members.take(1).toList();
    final personas = <String, Object?>{};
    for (final id in members) {
      final c = await character(id);
      if (c != null) {
        personas[id] = {
          'name': c.name,
          'personality': c.personality,
          'speech': c.speakingStyle,
        };
      }
    }
    final raw = await generate([
      {
        'role': 'system',
        'content':
            '你是群聊导演。根据最近话题、点名、性格选择0至2位最有理由说话的角色，不要机械轮流。仅返回角色ID的JSON数组。角色：${jsonEncode(personas)}',
      },
      {
        'role': 'user',
        'content': history.reversed
            .take(12)
            .map((m) => '${m.characterId}: ${m.text('content')}')
            .join('\n'),
      },
    ]);
    final decoded = parseJson(raw);
    if (decoded is! List) throw StateError('群聊发言选择格式错误，可重试');
    return decoded
        .whereType<String>()
        .where(members.contains)
        .toSet()
        .take(2)
        .toList();
  }

  Future<void> send(
    SocialRecord conversation,
    String text, {
    void Function(String, String)? onChunk,
    String? retryId,
    Future<void> Function(bool isReply)? onMessageSaved,
    bool deferMemory = false,
  }) async {
    if (!_generating.add(conversation.id)) throw StateError('正在回复，请稍候');
    try {
      if (retryId == null) {
        if (text.trim().isEmpty) return;
        await repository.save(
          SocialRecord.create(
            'message',
            {'content': text.trim(), 'sender': 'user', 'status': 'sent'},
            worldId: conversation.worldId,
            parentId: conversation.id,
            characterId: 'user',
          ),
        );
      }
      await onMessageSaved?.call(false);
      var history = await repository.list(
        'message',
        parentId: conversation.id,
        limit: 30,
      );
      final request = history
          .where((m) => m.text('sender') == 'user')
          .firstOrNull;
      if (request == null) return;
      final turnId = stable('turn:${request.id}');
      var turn = await repository.get(turnId);
      if (turn == null) {
        turn = SocialRecord.create(
          'turn',
          {'speakers': await _speakers(conversation, history)},
          id: turnId,
          parentId: conversation.id,
          worldId: conversation.worldId,
        );
        await repository.save(turn);
      }
      final speakers = turn.strings('speakers');
      final preferencesValue = await preferences();
      final world = await repository.get(conversation.worldId);
      for (final id in speakers) {
        final responseId = stable('reply:${request.id}:$id');
        if (await repository.get(responseId) != null) continue;
        final card = await character(id);
        final contact = await contactFor(id, conversation.worldId);
        if (card == null || contact == null || contact.deleted) continue;
        final profile = SocialProfileInferencer.infer(card);
        if (!preferencesValue.flag('instantReply', true)) {
          await Future<void>.delayed(
            Duration(seconds: profile.replySeconds.clamp(0, 5)),
          );
        }
        final memories = SocialMemoryRetriever.retrieve(
          (await repository.list('memory', characterId: id, limit: 100))
              .where(
                (m) =>
                    m.text('scope') != MemoryScope.globalCharacter.name ||
                    preferencesValue.flag('sharedMemory'),
              )
              .toList(),
          text,
          id,
          conversation.worldId,
          participants: conversation.flag('group')
              ? conversation.strings('members')
              : [],
        );
        final moments =
            (await repository.list(
                  'post',
                  worldId: conversation.worldId,
                  limit: 20,
                ))
                .where(
                  (p) =>
                      SocialVisibilityFilter.allows(
                        p,
                        viewer: id,
                        worldId: conversation.worldId,
                      ) &&
                      (!conversation.flag('group') ||
                          conversation
                              .strings('members')
                              .every(
                                (member) => SocialVisibilityFilter.allows(
                                  p,
                                  viewer: member,
                                  worldId: conversation.worldId,
                                ),
                              )),
                )
                .toList();
        final events = (await repository.list(
          'event',
          characterId: id,
          worldId: conversation.worldId,
          limit: 8,
        )).where((e) => e.text('visibility') == 'PUBLIC_SOCIAL').toList();
        final system = SocialPromptBuilder.build(
          card: card,
          contact: contact.change({
            'profile': profile.toJson(),
            'schedule': CharacterSchedule.at(card, profile, DateTime.now()),
          }),
          memories: memories,
          moments: moments,
          events: events,
          world: world?.text('publicLore') ?? '',
          interactions:
              (await Future.wait(
                    moments
                        .take(4)
                        .map(
                          (p) => repository.list(
                            'comment',
                            parentId: p.id,
                            limit: 4,
                          ),
                        ),
                  ))
                  .expand((v) => v)
                  .map((v) => '${v.characterId}：${v.text('content')}')
                  .join('\n'),
          group: conversation.flag('group'),
        );
        final response = await generate([
          {'role': 'system', 'content': system},
          ...SocialPromptBuilder.recentHistory(history).map(
            (m) => <String, String>{
              'role': m.text('sender') == 'user' ? 'user' : 'assistant',
              'content': SocialPromptBuilder.clipped(
                conversation.flag('group')
                    ? '${m.characterId}: ${m.text('content')}'
                    : m.text('content'),
                1500,
              ),
            },
          ),
        ], onChunk: (value) => onChunk?.call(id, value));
        final message = SocialRecord.create(
          'message',
          {'content': response, 'sender': 'character', 'status': 'delivered'},
          id: responseId,
          worldId: conversation.worldId,
          parentId: conversation.id,
          characterId: id,
        );
        await repository.save(message);
        await onMessageSaved?.call(true);
        for (final memory in memories) {
          final current = await repository.get(memory.id);
          if (current != null && !current.deleted) {
            await repository.save(
              current.change({
                'referenceCount': current.number('referenceCount') + 1,
                'lastReferencedAt': DateTime.now().millisecondsSinceEpoch,
              }),
            );
          }
        }
        history = [message, ...history];
        // Extraction failure must never lose or duplicate an already completed reply.
        Future<void> extract() async {
          if (_disposed) return;
          try {
            await _remember(
              contact,
              conversation,
              text,
              response,
              sourceMessageId: message.id,
            );
          } catch (_) {
            /* optional extraction must not invalidate the saved reply */
          }
        }

        if (deferMemory) {
          _memoryTail = _memoryTail.then((_) => extract());
        } else {
          await extract();
        }
      }
    } finally {
      _generating.remove(conversation.id);
    }
  }

  Future<void> _remember(
    SocialRecord contact,
    SocialRecord conversation,
    String userText,
    String reply, {
    String? sourceMessageId,
  }) async {
    if (userText.trim().isEmpty) return;
    final transcript = '$userText\n$reply';
    final raw = await generate([
      {
        'role': 'system',
        'content':
            '仅提取对话中明确发生的重要事实，不推测用户身份。返回JSON对象：memories数组，每项content,type,importance(1-10),evidence(原文逐字引用)；event为support/conflict/neutral；relationshipDelta为基于证据的小幅关系变化对象，允许familiarity/trust/closeness/attachment/respect/tension/jealousy/dependence/wariness，每项-3至3，无依据填0。不要把普通礼貌视为恋爱或依赖。没有重要信息返回空数组。',
      },
      {
        'role': 'user',
        'content': SocialPromptBuilder.clipped(transcript, 6000),
      },
    ], automatic: true);
    final value = parseJson(raw);
    if (value is! Map) return;
    if (_disposed) return;
    if (sourceMessageId != null) {
      final source = await repository.get(sourceMessageId);
      if (source == null || source.deleted) return;
    }
    final records = <SocialRecord>[];
    for (final memory in SocialMemoryExtractor.validate(
      value['memories'],
      transcript,
    )) {
      records.add(
        SocialRecord.create(
          'memory',
          {
            ...memory,
            'knownBy': ['user', ...conversation.strings('members')],
            'scope': MemoryScope.social.name,
          },
          worldId: contact.worldId,
          characterId: contact.characterId,
          parentId: conversation.id,
        ),
      );
    }
    // Only evidence-bearing interaction may affect relationships. No automatic romance.
    if (records.isNotEmpty) {
      final current = await repository.get(contact.id);
      if (current == null || current.deleted) return;
      final event = value['event'];
      final fallbackDelta = event == 'support'
          ? {'trust': 2, 'closeness': 1, 'familiarity': 1}
          : event == 'conflict'
          ? {'trust': -2, 'tension': 3, 'wariness': 1}
          : {'familiarity': 1};
      final delta = value['relationshipDelta'] is Map
          ? <String, Object?>{
              for (final key in SocialRelationshipState.dimensions)
                if ((value['relationshipDelta'] as Map)[key] is num)
                  key: ((value['relationshipDelta'] as Map)[key] as num).clamp(
                    -3,
                    3,
                  ),
            }
          : fallbackDelta;
      records.add(
        current.change({
          'relationship': SocialRelationshipState.apply(
            (current.data['relationship'] as Map? ?? {})
                .cast<String, Object?>(),
            delta,
          ),
          'mood': MoodTransitionResolver.resolve(
            (current.data['mood'] as Map? ?? {}).cast<String, Object?>(),
            event as String? ?? 'neutral',
          ),
          'lastInteraction': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    }
    await repository.saveAll(records);
  }

  Future<void> catchUp({DateTime? now}) async {
    if (_catchingUp || _generating.isNotEmpty) return;
    _catchingUp = true;
    try {
      final prefs = await preferences();
      if (!prefs.flag('autoLife', true)) return;
      final time = now ?? DateTime.now();
      for (final contact in await repository.list('contact', limit: 200)) {
        if (_disposed) break;
        if (!contact.flag('enabled', true)) continue;
        final elapsed =
            time.millisecondsSinceEpoch -
            contact.number('lastSimulated', time.millisecondsSinceEpoch);
        if (elapsed < const Duration(hours: 1).inMilliseconds) continue;
        final card = await character(contact.characterId);
        if (card == null) continue;
        final profile = SocialProfileInferencer.infer(card);
        final schedule = CharacterSchedule.at(card, profile, time);
        final world = await repository.get(contact.worldId);
        final factor = world?.text('timeMode') == 'accelerated' ? 24 : 1;
        final hours = (elapsed / 3600000 * factor).clamp(0, 72);
        // At most one event per contact per catch-up, including long absences.
        var event = SocialRecord.create(
          'event',
          {
            'content': '按日程进行了${schedule['activity']}。',
            'type': 'DAILY',
            'visibility': 'PUBLIC_SOCIAL',
            'source': 'schedule',
            'importance': 2,
          },
          worldId: contact.worldId,
          characterId: card.id,
          now: time,
        );
        final worldEvents = await repository.list(
          'event',
          worldId: contact.worldId,
          characterId: '',
          limit: 4,
        );
        final publicEvents = worldEvents
            .where(
              (e) =>
                  e.createdAt > contact.number('lastSimulated') &&
                  e.text('visibility') == 'PUBLIC_SOCIAL',
            )
            .toList();
        if (publicEvents.isNotEmpty) {
          event = SocialRecord.create(
            'event',
            {
              'content':
                  '${publicEvents.map((e) => e.text('content')).join('；')}。${event.text('content')}',
              'type': 'WORLD_EVENT',
              'visibility': 'PUBLIC_SOCIAL',
              'source': 'world',
              'importance': 6,
            },
            worldId: contact.worldId,
            characterId: card.id,
            now: time,
          );
        }
        if (prefs.text('quality') == 'rich' && hours >= 6) {
          try {
            final content = await generate([
              {
                'role': 'system',
                'content':
                    '根据角色身份、目标、日程与公开世界事件，推演一件过去时段的普通生活事件。最多120字，只写角色自己的经历，不涉及用户私聊、秘密、灾难或重大不可逆剧情。${SocialPromptBuilder.persona(card)}',
              },
              {
                'role': 'user',
                'content':
                    '过去${hours.round()}小时，${event.text('content')}。世界公开资料：${SocialPromptBuilder.clipped(world?.text('publicLore') ?? '', 1000)}',
              },
            ], automatic: true);
            event = SocialRecord.create(
              'event',
              {
                'content': SocialPromptBuilder.clipped(content, 300),
                'type': 'DAILY',
                'visibility': 'PUBLIC_SOCIAL',
                'source': 'rich_simulation',
                'importance': 5,
              },
              worldId: contact.worldId,
              characterId: card.id,
              now: time,
            );
          } on SocialBudgetExhausted {
            /* retain deterministic schedule event */
          } catch (_) {
            continue; /* failed life inference leaves previous state/cursor intact */
          }
        }
        final writes = <SocialRecord>[event];
        final lastPost = contact.number('lastPost');
        var nextPost = lastPost;
        var nextProactive = contact.number('lastProactive');
        final canPost =
            profile.postFrequency > 0 &&
            prefs.flag('autoMoments', true) &&
            prefs.text('quality', 'lowCost') != 'lowCost' &&
            hours >= 6 &&
            time.millisecondsSinceEpoch - lastPost >=
                (86400000 / profile.postFrequency).round();
        if (canPost) {
          try {
            final content = await generate([
              {
                'role': 'system',
                'content':
                    '以该角色发一条10至120字的日常动态。只依据给定公开事件，不编造秘密或用户经历，不要写作文。若不想发帖只返回SKIP。${SocialPromptBuilder.persona(card)}',
              },
              {
                'role': 'user',
                'content':
                    '公开事件：${event.text('content')}；风格：${profile.postingStyle}；当前情绪：${jsonEncode(contact.data['mood'])}。只表达心情，不编造或公开私人对话的具体原因。',
              },
            ], automatic: true);
            if (content != 'SKIP' && content.length <= 500) {
              writes.add(
                SocialRecord.create(
                  'post',
                  {
                    'content': content,
                    'visibility': 'PUBLIC_SOCIAL',
                    'eventSourceId': event.id,
                    'mediaType': 'TEXT',
                  },
                  worldId: contact.worldId,
                  characterId: card.id,
                  now: time,
                ),
              );
              nextPost = time.millisecondsSinceEpoch;
            }
          } catch (_) {
            /* no empty post; rules remain valid */
          }
        }
        if (prefs.flag('proactive') &&
            profile.initiative >= .5 &&
            hours >= 24 &&
            time.millisecondsSinceEpoch - nextProactive >= 86400000 &&
            (!prefs.flag('quietHours', true) ||
                (time.hour >= 8 && time.hour < 22))) {
          try {
            final content = await generate([
              {
                'role': 'system',
                'content':
                    '以该角色主动给用户发一条简短消息。不要编造共同经历。仅根据自己的日常事件，也可以只返回SKIP。${SocialPromptBuilder.persona(card)}',
              },
              {'role': 'user', 'content': event.text('content')},
            ], automatic: true);
            if (content != 'SKIP') {
              writes.add(
                SocialRecord.create(
                  'message',
                  {
                    'content': content,
                    'sender': 'character',
                    'status': 'delivered',
                    'proactive': true,
                  },
                  worldId: contact.worldId,
                  characterId: card.id,
                  parentId: stable('dm:${contact.id}'),
                  now: time,
                ),
              );
              nextProactive = time.millisecondsSinceEpoch;
            }
          } catch (_) {
            /* cost/network failure does not create fake messages */
          }
        }
        writes.add(
          contact.change({
            'profile': profile.toJson(),
            'schedule': schedule,
            if (schedule['activity'] == '休息')
              'mood': MoodTransitionResolver.resolve(
                (contact.data['mood'] as Map? ?? {}).cast<String, Object?>(),
                'rest',
              ),
            'lastSimulated': time.millisecondsSinceEpoch,
            'lastPost': nextPost,
            'lastProactive': nextProactive,
          }),
        );
        await repository.saveAll(writes);
        // Reactions are optional and budgeted; the committed life event/post
        // remains valid even if the provider is unavailable afterwards.
        for (final post in writes.where((record) => record.kind == 'post')) {
          try {
            await react(post);
          } catch (_) {
            // Never roll back a published post because a reaction failed.
          }
        }
      }
    } finally {
      _catchingUp = false;
    }
  }

  Future<void> clearConversation(
    SocialRecord conversation, {
    required bool clearMemories,
  }) async {
    if (_generating.contains(conversation.id)) {
      throw StateError('请等待当前回复结束后再清理');
    }
    for (final kind in ['message', if (clearMemories) 'memory']) {
      while (true) {
        final rows = await repository.list(
          kind,
          parentId: conversation.id,
          limit: 25,
        );
        if (rows.isEmpty) break;
        await repository.saveAll(
          rows.map((r) => r.change({}, deleted: true)).toList(),
        );
      }
    }
  }

  Future<void> publish(
    String content,
    String worldId, {
    List<String> audience = const [],
  }) async {
    if (content.trim().isEmpty || content.length > 3000) {
      throw StateError('动态内容需要1至3000字');
    }
    final post = SocialRecord.create(
      'post',
      {
        'content': content.trim(),
        'visibility': audience.isEmpty
            ? 'PUBLIC_SOCIAL'
            : 'SELECTED_CHARACTERS',
        'audience': audience,
      },
      worldId: worldId,
      characterId: 'user',
    );
    await repository.save(post);
    await react(post);
  }

  Future<void> like(SocialRecord post, {String author = 'user'}) async {
    final id = stable('like:${post.id}:$author');
    final old = await repository.get(id);
    await repository.save(
      old == null
          ? SocialRecord.create(
              'like',
              {},
              id: id,
              worldId: post.worldId,
              parentId: post.id,
              characterId: author,
            )
          : old.change({}, deleted: !old.deleted),
    );
    if (author == 'user' && post.characterId != 'user') {
      final count = await repository.likesFor(post.characterId);
      final id = stable(
        'like-pattern:${post.worldId}:${post.characterId}:${count ~/ 5}',
      );
      if (count >= 5 && count % 5 == 0 && await repository.get(id) == null) {
        await repository.save(
          SocialRecord.create(
            'memory',
            {
              'content': '用户近期点赞了你发布的 $count 条动态。',
              'type': 'LIKE_INTERACTION',
              'scope': 'social',
              'importance': 5,
              'knownBy': ['user', post.characterId],
              'decayPolicy': 'slow',
            },
            id: id,
            worldId: post.worldId,
            characterId: post.characterId,
          ),
        );
      }
    }
  }

  Future<void> comment(SocialRecord post, String content) async {
    if (content.trim().isEmpty) return;
    await repository.save(
      SocialRecord.create(
        'comment',
        {'content': content.trim()},
        worldId: post.worldId,
        parentId: post.id,
        characterId: 'user',
      ),
    );
    await react(post, userComment: content);
  }

  Future<void> react(SocialRecord post, {String? userComment}) async {
    final contacts = await repository.list(
      'contact',
      worldId: post.worldId,
      limit: 200,
    );
    var count = 0;
    for (final contact in contacts) {
      if (count >= 2) break;
      if (!contact.flag('enabled', true)) continue;
      // Authors may answer a user's comment, but should not spend a model call
      // liking/commenting on their own freshly published moment.
      if (post.characterId == contact.characterId && userComment == null) {
        continue;
      }
      if (!SocialVisibilityFilter.allows(
        post,
        viewer: contact.characterId,
        worldId: contact.worldId,
      )) {
        continue;
      }
      if (post.characterId != 'user' &&
          post.characterId != contact.characterId) {
        final pair = [post.characterId, contact.characterId]..sort();
        if (await repository.get(
              stable('edge:${post.worldId}:${pair.join(':')}'),
            ) ==
            null) {
          continue;
        }
      }
      final card = await character(contact.characterId);
      if (card == null) continue;
      final profile = SocialProfileInferencer.infer(card);
      if (profile.initiative < .5 &&
          !(userComment != null && post.characterId == card.id)) {
        continue;
      }
      count++;
      try {
        final response = await generate([
          {
            'role': 'system',
            'content':
                '你是角色。决定是否回应可见动态。只返回JSON：like布尔值，comment字符串（可为空）。评论通常少于60字，不知道别人的私聊。${SocialPromptBuilder.persona(card)}',
          },
          {
            'role': 'user',
            'content': '动态：${post.text('content')}\n用户评论：${userComment ?? ''}',
          },
        ], automatic: true);
        final value = parseJson(response);
        if (value is! Map) continue;
        final writes = <SocialRecord>[];
        final likeId = stable('like:${post.id}:${card.id}');
        if (value['like'] == true && await repository.get(likeId) == null) {
          writes.add(
            SocialRecord.create(
              'like',
              {},
              id: likeId,
              worldId: post.worldId,
              parentId: post.id,
              characterId: card.id,
            ),
          );
        }
        final text = value['comment'] as String? ?? '';
        if (text.trim().isNotEmpty && text.length <= 300) {
          writes.add(
            SocialRecord.create(
              'comment',
              {'content': text},
              worldId: post.worldId,
              parentId: post.id,
              characterId: card.id,
            ),
          );
        }
        await repository.saveAll(writes);
        if (userComment != null && text.trim().isNotEmpty) {
          try {
            await _remember(
              contact,
              SocialRecord.create(
                'conversation',
                {
                  'members': [card.id],
                },
                id: post.id,
                worldId: post.worldId,
              ),
              userComment,
              text,
            );
          } catch (_) {
            /* saved comments remain available as recent context */
          }
        }
      } catch (_) {
        /* optional social response; user content is already saved */
      }
    }
  }
}
