import '../../app/skins/skin_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../app/skins/theme_background.dart';
import 'package:uuid/uuid.dart';

import '../../models/api_profile.dart';
import '../../models/trpg_game_models.dart';
import '../../models/trpg_gameplay_models.dart';
import '../../models/trpg_models.dart';
import '../../models/trpg_presentation_models.dart';
import '../../models/trpg_dice_models.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/trpg_session_repository.dart';
import '../../services/ai_service.dart';
import '../../services/trpg/ai_gm_output_guard.dart';
import '../../services/trpg/ai_gm_service.dart';
import '../../services/trpg/dice_service.dart';
import '../../services/trpg/trpg_save_queue.dart';
import '../../services/trpg/trpg_audio_director.dart';
import '../../services/trpg/trpg_presentation_service.dart';
import '../../services/voice/sherpa_text_to_speech_service.dart';
import '../../services/voice/voice_model_manager.dart';
import '../trpg_shared/trpg_immersion_panel.dart';
import '../trpg_shared/trpg_presentation_stage.dart';
import '../trpg_shared/trpg_memory_screen.dart';
import '../trpg_shared/trpg_play_ui.dart';
import '../trpg_shared/trpg_player_guide_card.dart';
import '../trpg_shared/trpg_voice_button.dart';
import '../trpg_shared/trpg_private_mailbox_screen.dart';
import '../trpg_shared/dice_panel.dart';
import '../app_settings/skin_gallery_page.dart';

/// Reads event payloads written by both legacy and current campaign builders.
///
/// Initial ordinary campaigns store `scene` as opening text, while later tool
/// calls store it as a JSON map.  This function must therefore never cast the
/// value to a map unconditionally.
String trpgEventPayloadLabel(Object? value, List<String> preferredKeys) {
  if (value == null) return '';
  if (value is Map) {
    for (final key in preferredKeys) {
      final candidate = value[key];
      if (candidate != null && candidate.toString().trim().isNotEmpty) {
        return candidate.toString();
      }
    }
    return value.values
        .where((candidate) => candidate != null)
        .map((candidate) => candidate.toString())
        .firstWhere(
          (candidate) => candidate.trim().isNotEmpty,
          orElse: () => '',
        );
  }
  return value.toString();
}

enum _SoloComposerMode { action, chat, secret }

class SoloSessionScreen extends StatefulWidget {
  const SoloSessionScreen({
    required this.session,
    required this.repository,
    required this.apiRepository,
    required this.settingsRepository,
    required this.aiService,
    super.key,
  });

  final TRPGSession session;
  final TRPGSessionRepository repository;
  final ApiRepository apiRepository;
  final SettingsRepository settingsRepository;
  final AiService aiService;

  @override
  State<SoloSessionScreen> createState() => _SoloSessionScreenState();
}

class _SoloSessionScreenState extends State<SoloSessionScreen>
    with WidgetsBindingObserver {
  static const _uuid = Uuid();
  late TRPGSession _session;
  late final AIGMService _gm;
  late final TRPGSaveQueue _saveQueue;
  late final TRPGPresentationService _presentation;
  late final TRPGAudioDirector _audio;
  late final SherpaTextToSpeechService _speech;
  final _dice = DiceService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _autoSaveEnabled = true;
  bool _diceAnimationEnabled = true;
  int _gmOutputLength = 2000;
  bool _autoSpeakNpc = true;
  bool _autoSpeakNarrator = true;
  bool _ttsEnabled = false;
  bool _memoryDebug = false;
  bool? _showPresentationStage;
  _SoloComposerMode _composerMode = _SoloComposerMode.action;
  final Set<String> _unreadPrivateContactIds = {};
  String? _error;
  String? _failedAction;
  String? _failedActionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = widget.session;
    _gm = AIGMService(widget.aiService);
    _saveQueue = TRPGSaveQueue(widget.repository);
    _presentation = TRPGPresentationService(
      initialState: _session.presentationState,
    )..addListener(_onPresentationChanged);
    _audio = TRPGAudioDirector();
    _speech = SherpaTextToSpeechService(VoiceModelManager());
    _presentation.events.listen((event) => unawaited(_audio.handle(event)));
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final settings = await widget.settingsRepository.load();
    if (!mounted) return;
    setState(() {
      _autoSaveEnabled = settings.trpgAutoSave;
      _diceAnimationEnabled = settings.trpgDiceAnimation;
      _gmOutputLength = settings.trpgGmOutputLength;
      _autoSpeakNpc = settings.trpgAutoSpeakNpc;
      _autoSpeakNarrator = settings.trpgAutoSpeakNarrator;
      _ttsEnabled = settings.voiceSettings.ttsEnabled;
      _memoryDebug = settings.debugMode;
      _gm.memoryTokenBudget = settings.trpgMemoryTokenBudget;
      _presentation.restore(
        _session.presentationState.copyWith(
          presentationMode: settings.trpgPresentationMode,
          quality: settings.trpgPresentationQuality,
        ),
      );
      _audio
        ..masterVolume = settings.trpgMasterVolume
        ..bgmVolume = settings.trpgBgmVolume
        ..ambientVolume = settings.trpgAmbientVolume
        ..sfxVolume = settings.trpgSfxVolume
        ..voiceVolume = settings.trpgVoiceVolume;
    });
  }

  void _onPresentationChanged() {
    _session = _session.copyWith(presentationState: _presentation.state);
    if (mounted) setState(() {});
  }

  Future<void> _presentMutation(TRPGSession before, TRPGSession after) async {
    final events = const AIPresentationDirector().derive(
      before: before,
      after: after,
    );
    await _presentation.enqueueAll(events);
    _session = after.copyWith(presentationState: _presentation.state);
    final newMessages = after.chatHistory.where(
      (value) => !before.chatHistory.any((old) => old.id == value.id),
    );
    for (final message in newMessages) {
      if ((message.messageType == TRPGMessageType.npcMessage ||
                  message.messageType == TRPGMessageType.npcPlayerMessage) &&
              _autoSpeakNpc ||
          message.messageType == TRPGMessageType.gmMessage &&
              _autoSpeakNarrator) {
        await _speak(message);
      }
    }
  }

  Future<void> _speak(TRPGMessage message) async {
    if (!_ttsEnabled) return;
    final settings = await widget.settingsRepository.load();
    final npcId = message.presentation.speakerId ?? message.npcId;
    final voice = settings.voiceSettings
        .voiceFor(npcId)
        .copyWith(volume: settings.trpgVoiceVolume);
    await _speech.speak(
      message.content,
      voice: voice,
      messageId: message.id,
      speakNarration: true,
    );
  }

  Future<void> _skipPresentation() async {
    _presentation.skip();
    await _speech.stop();
  }

  Future<void> _save() async {
    _session = _session.copyWith(
      updatedAt: DateTime.now(),
      lastPlayedAt: DateTime.now(),
    );
    await widget.repository.upsert(_session);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_autoSaveEnabled) unawaited(_save());
    }
  }

  Future<ApiProfile?> _profile() async {
    final profiles = await widget.apiRepository.getAll();
    return profiles
            .where((item) => item.id == _session.gmProviderConfigRef)
            .firstOrNull ??
        profiles.firstOrNull;
  }

  Future<void> _send() async {
    final action = _input.text.trim();
    if (action.isEmpty || _sending) return;

    final profile = await _profile();
    if (profile == null) {
      setState(() => _error = '尚未配置 AI API，请先在应用设置中添加。');
      return;
    }

    if (_composerMode != _SoloComposerMode.action) {
      await _sendSideInteraction(
        action,
        profile,
        _composerMode == _SoloComposerMode.chat
            ? SoloAIInteractionType.tableChat
            : SoloAIInteractionType.secretAction,
      );
      return;
    }

    final now = DateTime.now();
    final actionMessage = TRPGMessage(
      id: _uuid.v4(),
      messageType: TRPGMessageType.playerMessage,
      content: action,
      playerId: _session.players.firstOrNull?.playerId,
      createdAt: now,
    );
    final actionEvent = TRPGEvent(
      id: actionMessage.id,
      type: TRPGEventType.playerAction,
      timestamp: now,
      actorId: _session.players.firstOrNull?.playerId,
      payload: {
        'action': action,
        'actionId': actionMessage.id,
        'turnId': actionMessage.id,
        'characterId': _session.playerCharacters.firstOrNull?.id,
      },
    );

    setState(() {
      _sending = true;
      _error = null;
      _failedAction = null;
      _failedActionId = null;
      _session = _session.copyWith(
        chatHistory: [..._session.chatHistory, actionMessage],
        eventLog: [..._session.eventLog, actionEvent],
        updatedAt: now,
        lastPlayedAt: now,
      );
    });
    _input.clear();

    // 玩家行动先落盘。即便网络失败，退出并重新进入后也不会丢失行动。
    if (_autoSaveEnabled) await _save();

    try {
      final beforeAi = _session;
      final key = await widget.apiRepository.readApiKey(profile.id);
      final afterAi = await _gm.respondToRecordedAction(
        session: _session,
        action: action,
        profile: profile.copyWith(maxTokens: _gmOutputLength),
        apiKey: key,
        actionId: actionMessage.id,
        onToolMutation: (mutated) async {
          _session = mutated;
          if (_autoSaveEnabled) await _saveQueue.enqueue(mutated);
          if (mounted) setState(() {});
        },
      );
      await _presentMutation(beforeAi, afterAi);
      final privateIdsBefore = _session.immersionState.privateMessages
          .map((message) => message.id)
          .toSet();
      try {
        final withPrivateEvent = await _gm.maybeTriggerSoloPrivateMessage(
          session: _session,
          profile: profile.copyWith(maxTokens: _gmOutputLength),
          apiKey: key,
          sourceActionId: actionMessage.id,
        );
        final incoming = withPrivateEvent.immersionState.privateMessages
            .where((message) => !privateIdsBefore.contains(message.id))
            .lastOrNull;
        _session = withPrivateEvent;
        if (incoming != null && mounted) {
          final senderName = _resolvePrivateName(incoming.senderId);
          setState(() => _unreadPrivateContactIds.add(incoming.senderId));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('收到 $senderName 的新私信'),
              action: SnackBarAction(
                label: '查看',
                onPressed: () => unawaited(_showPrivateChannel()),
              ),
            ),
          );
        }
      } catch (error) {
        debugPrint('Random solo private message skipped: $error');
      }
      if (_autoSaveEnabled) await _save();
      if (!mounted) return;
      setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (_scroll.hasClients) {
        await _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'AI 主持暂时无法响应：$error';
          _failedAction = action;
          _failedActionId = actionMessage.id;
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendSideInteraction(
    String content,
    ApiProfile profile,
    SoloAIInteractionType type, {
    String? targetPlayerId,
    String? targetName,
    bool clearComposer = true,
  }) async {
    setState(() {
      _sending = true;
      _error = null;
      _failedAction = null;
      _failedActionId = null;
    });
    if (clearComposer) _input.clear();
    try {
      final key = await widget.apiRepository.readApiKey(profile.id);
      final updated = await _gm.handleSoloInteraction(
        session: _session,
        content: content,
        type: type,
        targetPlayerId: targetPlayerId,
        targetName: targetName,
        profile: profile.copyWith(maxTokens: _gmOutputLength),
        apiKey: key,
      );
      if (!mounted) return;
      setState(() => _session = updated);
      if (_autoSaveEnabled) await _save();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (_scroll.hasClients && type == SoloAIInteractionType.tableChat) {
        await _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    } catch (error) {
      if (!mounted) return;
      if (clearComposer) _input.text = content;
      setState(() => _error = 'AI 私密频道暂时无法响应：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _retry() async {
    final action = _failedAction;
    final actionId = _failedActionId;
    if (action == null || actionId == null || _sending) return;
    final profile = await _profile();
    if (profile == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final beforeAi = _session;
      final key = await widget.apiRepository.readApiKey(profile.id);
      final afterAi = await _gm.respondToRecordedAction(
        session: _session,
        action: action,
        actionId: actionId,
        profile: profile.copyWith(maxTokens: _gmOutputLength),
        apiKey: key,
        onToolMutation: (mutated) async {
          _session = mutated;
          if (_autoSaveEnabled) await _saveQueue.enqueue(mutated);
          if (mounted) setState(() {});
        },
      );
      await _presentMutation(beforeAi, afterAi);
      if (_autoSaveEnabled) await _save();
      if (mounted) {
        setState(() {
          _failedAction = null;
          _failedActionId = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '重试失败：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<DiceRollResult> _rollFormula(String formula) async {
    final result = _dice.rollResult(
      formula: formula,
      playerId: _session.players.first.playerId,
      action: '玩家主动投骰',
      reason: '玩家从骰子面板进行手动投骰',
      rulePackage: _session.ruleState.diceSettings.rulePackage,
    );
    final before = _session;
    final after = _dice.recordResult(_session, result);
    setState(() => _session = after);
    await _presentMutation(before, after);
    if (_autoSaveEnabled) await _save();
    return result;
  }

  Future<void> _updateDiceSettings(DiceSettings settings) async {
    setState(() {
      _session = _session.copyWith(
        ruleState: _session.ruleState.copyWith(diceSettings: settings),
        updatedAt: DateTime.now(),
      );
    });
    if (_autoSaveEnabled) await _save();
  }

  List<Widget> _panelContent(BuildContext context, String type) {
    final character = _session.playerCharacters.first;
    switch (type) {
      case 'character':
        return [
          Text('角色', style: Theme.of(context).textTheme.headlineSmall),
          ..._session.playerCharacters.map((entry) {
            final isAi = _session.players.any(
              (player) =>
                  player.playerId == entry.playerId && player.isAiControlled,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: CircleAvatar(
                    child: SkinIcon(
                      isAi ? Icons.smart_toy_outlined : Icons.person,
                    ),
                  ),
                  title: Text(entry.name),
                  subtitle: Text(
                    '${isAi ? 'AI 玩家' : '你的角色'} · HP ${entry.hp}/${entry.maxHp}',
                  ),
                ),
                ...entry.stats.entries.map(
                  (stat) => ListTile(
                    dense: true,
                    title: Text(stat.key),
                    trailing: Text('${stat.value}'),
                  ),
                ),
                if (entry.skills.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('技能'),
                  ),
                  ...entry.skills.entries.map(
                    (skill) => ListTile(
                      dense: true,
                      title: Text(skill.key),
                      trailing: Text('${skill.value}'),
                    ),
                  ),
                ],
                if (_session.ruleState.traits
                    .where((trait) => trait.characterId == entry.id)
                    .isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('特质'),
                  ),
                  ..._session.ruleState.traits
                      .where((trait) => trait.characterId == entry.id)
                      .map(
                        (trait) => ListTile(
                          dense: true,
                          leading: const SkinIcon(Icons.auto_awesome_outlined),
                          title: Text(trait.name),
                          subtitle: Text(trait.description),
                        ),
                      ),
                ],
                if (_session.ruleState.growthHistory
                    .where((growth) => growth.characterId == entry.id)
                    .isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('最近成长'),
                  ),
                  ..._session.ruleState.growthHistory
                      .where((growth) => growth.characterId == entry.id)
                      .toList()
                      .reversed
                      .take(5)
                      .map(
                        (growth) => ListTile(
                          dense: true,
                          leading: const SkinIcon(Icons.trending_up),
                          title: Text(growth.targetId),
                          subtitle: Text(growth.reason),
                          trailing: Text('${growth.before} → ${growth.after}'),
                        ),
                      ),
                ],
                const Divider(height: 1),
              ],
            );
          }),
        ];
      case 'inventory':
        return [
          Text('背包', style: Theme.of(context).textTheme.headlineSmall),
          if (character.inventoryItems.isEmpty)
            const ListTile(title: Text('背包还是空的')),
          ...character.inventoryItems.map(
            (item) => ListTile(
              leading: const SkinIcon(Icons.inventory_2_outlined),
              title: Text(item.name),
              subtitle: Text('${item.category.name} · ${item.description}'),
              trailing: Text('×${item.quantity}'),
            ),
          ),
        ];
      case 'quests':
        return [
          Text('任务与线索', style: Theme.of(context).textTheme.headlineSmall),
          const Text('进行中'),
          if (_session.campaignState.quests
              .where((quest) => quest.status == QuestStatus.active)
              .isEmpty)
            const ListTile(title: Text('暂无任务')),
          ..._session.campaignState.quests
              .where((quest) => quest.status == QuestStatus.active)
              .map(
                (quest) => ListTile(
                  leading: const SkinIcon(Icons.radio_button_unchecked),
                  title: Text(quest.title),
                  subtitle: Text(
                    quest.progress.isEmpty ? quest.description : quest.progress,
                  ),
                ),
              ),
          const Divider(),
          const Text('已完成'),
          ..._session.campaignState.quests
              .where((quest) => quest.status == QuestStatus.completed)
              .map(
                (quest) => ListTile(
                  leading: const SkinIcon(Icons.check_circle_outline),
                  title: Text(quest.title),
                ),
              ),
          const Divider(),
          const Text('失败'),
          ..._session.campaignState.quests
              .where((quest) => quest.status == QuestStatus.failed)
              .map(
                (quest) => ListTile(
                  leading: const SkinIcon(Icons.cancel_outlined),
                  title: Text(quest.title),
                ),
              ),
          const Divider(),
          const Text('已发现线索'),
          ..._session.campaignState.clues
              .where((clue) => clue.discovered)
              .map(
                (clue) => ListTile(
                  leading: const SkinIcon(Icons.search),
                  title: Text(clue.name),
                  subtitle: Text(clue.description),
                ),
              ),
        ];
      case 'dice':
        return [
          DicePanel(
            history: _session.ruleState.diceHistory2,
            settings: _session.ruleState.diceSettings.copyWith(
              animationEnabled:
                  _diceAnimationEnabled &&
                  _session.ruleState.diceSettings.animationEnabled,
            ),
            onRoll: _rollFormula,
            onSettingsChanged: _updateDiceSettings,
          ),
        ];
      default:
        return [
          Text('事件日志', style: Theme.of(context).textTheme.headlineSmall),
          ..._session.eventLog.reversed.map(
            (event) => ListTile(
              dense: true,
              leading: SkinIcon(
                event.type == TRPGEventType.diceRoll
                    ? Icons.casino_outlined
                    : Icons.history,
              ),
              title: Text(event.type.name),
              subtitle: Text(
                event.timestamp.toLocal().toString().substring(0, 16),
              ),
            ),
          ),
        ];
    }
  }

  void _showPanel(String type) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .55,
        maxChildSize: .9,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: _panelContent(context, type),
        ),
      ),
    );
  }

  Future<void> _openImmersion(TrpgPanelType type) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TrpgImmersionPanel(
          session: _session,
          type: type,
          playerId: _session.players.firstOrNull?.playerId,
          onSessionChanged: (updated) async {
            setState(() => _session = updated);
            await _save();
          },
        ),
      ),
    );
  }

  String _resolvePrivateName(String senderId) {
    if (senderId == 'gm') return 'GM 主持';
    if (senderId == 'system') return '私密系统';
    final player = _session.players
        .where((value) => value.playerId == senderId)
        .firstOrNull;
    final character = _session.playerCharacters
        .where((value) => value.playerId == senderId)
        .firstOrNull;
    final npc = _session.worldState.npcs
        .where((value) => value.npcId == senderId)
        .firstOrNull;
    return character?.name ?? player?.displayName ?? npc?.name ?? '未知联系人';
  }

  List<TrpgPrivateContact> _privateContacts() {
    final contacts = <TrpgPrivateContact>[
      const TrpgPrivateContact(
        id: 'gm',
        name: 'GM 主持',
        subtitle: '询问规则、进行秘密调查或与主持人私聊',
        isGm: true,
      ),
    ];
    for (final player in _session.players.where(
      (value) => value.isAiControlled,
    )) {
      contacts.add(
        TrpgPrivateContact(
          id: player.playerId,
          name: _resolvePrivateName(player.playerId),
          subtitle: 'AI 队友 · 会按自己的性格和立场回复',
        ),
      );
    }
    for (final npc in _session.worldState.npcs.where(
      (npc) =>
          npc.alive &&
          (npc.knownToPlayer ||
              _session.worldState.knownNpcs.contains(npc.npcId) ||
              _session.worldState.knownNpcs.contains(npc.name)),
    )) {
      if (contacts.any((contact) => contact.id == npc.npcId)) continue;
      contacts.add(
        TrpgPrivateContact(id: npc.npcId, name: npc.name, subtitle: '已认识的剧情人物'),
      );
    }
    return contacts;
  }

  Future<List<TRPGPrivateMessage>?> _sendPrivateToContact(
    TrpgPrivateContact target,
    String content,
  ) async {
    final profile = await _profile();
    if (profile == null) {
      throw StateError('尚未配置 AI API，请先在应用设置中添加');
    }
    final key = await widget.apiRepository.readApiKey(profile.id);
    final updated = await _gm.handleSoloInteraction(
      session: _session,
      content: content,
      type: SoloAIInteractionType.privateMessage,
      targetPlayerId: target.isGm ? null : target.id,
      targetName: target.name,
      profile: profile.copyWith(maxTokens: _gmOutputLength),
      apiKey: key,
    );
    _session = updated;
    if (mounted) setState(() {});
    if (_autoSaveEnabled) await _save();
    return updated.immersionState.privateMessages;
  }

  Future<void> _showPrivateChannel() async {
    final playerId = _session.players.firstOrNull?.playerId;
    if (playerId == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TrpgPrivateMailboxScreen(
          currentPlayerId: playerId,
          contacts: _privateContacts(),
          messages: _session.immersionState.privateMessages,
          resolveName: _resolvePrivateName,
          onSend: _sendPrivateToContact,
          initialUnreadContactIds: {..._unreadPrivateContactIds},
          onContactOpened: (id) {
            if (mounted) setState(() => _unreadPrivateContactIds.remove(id));
          },
        ),
      ),
    );
  }

  Future<void> _showPrivateDice() async {
    final formula = TextEditingController(text: '1D20');
    final reason = TextEditingController(text: '玩家主动私骰');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const SkinIcon(Icons.casino_outlined),
        title: const Text('私密投骰'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('点数只保存在你的私密频道，不会出现在公共聊天和公开事件中。'),
            const SizedBox(height: 12),
            TextField(
              controller: formula,
              decoration: const InputDecoration(
                labelText: '公式',
                hintText: '1D20、2D6+3、1D100+20',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: '投骰原因'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('投骰'),
          ),
        ],
      ),
    );
    final formulaText = formula.text.trim();
    final reasonText = reason.text.trim();
    formula.dispose();
    reason.dispose();
    if (confirmed != true || formulaText.isEmpty) return;

    try {
      final playerId = _session.players.first.playerId;
      final result = _dice.rollResult(
        formula: formulaText,
        playerId: playerId,
        action: '私密投骰',
        reason: reasonText,
        rulePackage: _session.ruleState.diceSettings.rulePackage,
        visibility: DiceVisibility.playerPrivate,
        ownerPlayerIds: [playerId],
      );
      final now = DateTime.now();
      final history = [..._session.ruleState.diceHistory2, result];
      final detail =
          '${result.diceFormula} = ${result.finalResult}'
          '${reasonText.isEmpty ? '' : '\n$reasonText'}';
      setState(() {
        _session = _session.copyWith(
          ruleState: _session.ruleState.copyWith(
            diceHistory2: history.length > 50
                ? history.sublist(history.length - 50)
                : history,
          ),
          immersionState: _session.immersionState.copyWith(
            privateMessages: [
              ..._session.immersionState.privateMessages,
              TRPGPrivateMessage(
                id: _uuid.v4(),
                senderId: 'system',
                recipientIds: [playerId],
                content: detail,
                createdAt: now,
                toGm: true,
              ),
            ],
            timeline: [
              ..._session.immersionState.timeline,
              SessionTimelineEntry(
                id: _uuid.v4(),
                title: '私密投骰 ${result.diceFormula} = ${result.finalResult}',
                detail: reasonText,
                createdAt: now,
                visibility: InformationVisibility.playerPrivate,
                ownerPlayerIds: [playerId],
              ),
            ],
          ),
          eventLog: [
            ..._session.eventLog,
            TRPGEvent(
              id: _uuid.v4(),
              type: TRPGEventType.privateRoll,
              timestamp: now,
              actorId: playerId,
              payload: {
                ...result.toJson(),
                'visibility': RollVisibility.playerPrivate.name,
                'visibilityPlayerIds': [playerId],
              },
              visibleToAi: false,
            ),
          ],
          updatedAt: now,
          lastPlayedAt: now,
        );
      });
      if (_autoSaveEnabled) await _save();
      if (mounted) _showPrivateChannel();
    } catch (error) {
      if (mounted) setState(() => _error = '私骰失败：$error');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_autoSaveEnabled) unawaited(_save());
    unawaited(_saveQueue.dispose());
    _gm.dispose();
    _presentation.removeListener(_onPresentationChanged);
    _presentation.dispose();
    unawaited(_audio.dispose());
    unawaited(_speech.dispose());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final character = _session.playerCharacters.first;
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final showPresentationStage = _showPresentationStage ?? false;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_session.title),
            Text(
              '第 ${_session.campaignState.currentAct} 幕 · ${_session.worldState.location}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '演出设置',
            icon: const SkinIcon(Icons.theater_comedy_outlined),
            onSelected: (value) {
              if (value == 'skin') {
                unawaited(
                  openSkinGallery(context, contextHint: _session.title),
                );
                return;
              }
              if (value == 'skip') {
                unawaited(_skipPresentation());
                return;
              }
              if (value == 'memory') {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TRPGMemoryScreen(
                      session: _session,
                      playerId: _session.players.firstOrNull?.playerId,
                      isGm: true,
                      debugMode: _memoryDebug,
                      onChanged: (updated) {
                        setState(() => _session = updated);
                        unawaited(_save());
                      },
                    ),
                  ),
                );
                return;
              }
              final mode = value == 'classic'
                  ? PresentationMode.classicChat
                  : PresentationMode.immersive;
              _presentation.restore(
                _presentation.state.copyWith(presentationMode: mode),
              );
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'immersive', child: Text('沉浸演出模式')),
              PopupMenuItem(value: 'classic', child: Text('简洁文字模式')),
              PopupMenuItem(value: 'skip', child: Text('跳过当前演出和语音')),
              PopupMenuItem(value: 'memory', child: Text('冒险记录 / 记忆管理')),
              PopupMenuItem(value: 'skin', child: Text('外观与皮肤')),
            ],
          ),
          PopupMenuButton<TrpgPanelType>(
            tooltip: '跑团信息',
            onSelected: _openImmersion,
            itemBuilder: (_) => const [
              PopupMenuItem(value: TrpgPanelType.clues, child: Text('线索板')),
              PopupMenuItem(value: TrpgPanelType.map, child: Text('地图')),
              PopupMenuItem(value: TrpgPanelType.people, child: Text('人物')),
              PopupMenuItem(value: TrpgPanelType.timeline, child: Text('事件日志')),
              PopupMenuItem(
                value: TrpgPanelType.recap,
                child: Text('上次发生了什么？'),
              ),
            ],
          ),
          IconButton(
            onPressed: () async {
              await _save();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('跑团进度已保存')));
              }
            },
            tooltip: '手动保存',
            icon: const SkinIcon(Icons.save_outlined),
          ),
        ],
      ),
      body: ThemeBackground(
        chat: true,
        child: Column(
          children: [
            if (_presentation.state.presentationMode ==
                    PresentationMode.immersive &&
                showPresentationStage)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TRPGPresentationStage(
                  session: _session,
                  service: _presentation,
                  compact: MediaQuery.sizeOf(context).height < 1000,
                  onReplayVoice: (message) => unawaited(_speak(message)),
                  onSkip: () => unawaited(_skipPresentation()),
                ),
              ),
            ExpansionTile(
              title: Text(
                '${_session.worldState.location} · HP ${character.hp}/${character.maxHp}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              children: [
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: TrpgSceneSummary(
                    dense: isNarrow,
                    title: _session.worldState.currentScene.title.isEmpty
                        ? _session.worldState.location
                        : _session.worldState.currentScene.title,
                    subtitle:
                        '${_session.worldState.time} · ${_session.worldState.weather}',
                    facts: [
                      TrpgFact(
                        Icons.favorite_outline,
                        'HP ${character.hp}/${character.maxHp}',
                      ),
                      TrpgFact(
                        Icons.health_and_safety_outlined,
                        character.statusEffects.isEmpty
                            ? '状态正常'
                            : character.statusEffects.join('、'),
                      ),
                      TrpgFact(
                        Icons.assignment_outlined,
                        _session.campaignState.quests
                                .where(
                                  (quest) => quest.status == QuestStatus.active,
                                )
                                .firstOrNull
                                ?.title ??
                            '暂无任务',
                      ),
                      if (_session.ruleState.combatActive)
                        TrpgFact(
                          Icons.sports_martial_arts_outlined,
                          '战斗 · 第 ${_session.ruleState.round} 回合',
                          emphasized: true,
                        ),
                    ],
                    trailing:
                        _presentation.state.presentationMode ==
                            PresentationMode.immersive
                        ? IconButton.filledTonal(
                            tooltip: showPresentationStage
                                ? '收起演出画面'
                                : '展开演出画面',
                            onPressed: () => setState(
                              () => _showPresentationStage =
                                  !showPresentationStage,
                            ),
                            icon: SkinIcon(
                              showPresentationStage
                                  ? Icons.expand_less_rounded
                                  : Icons.image_outlined,
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
            Expanded(
              child: TrpgTimelineViewport(
                controller: _scroll,
                children: _timelineWidgets(character.name),
              ),
            ),
            if (_error != null)
              TrpgInlineNotice(
                message: _error!,
                isError: true,
                action: _failedAction == null
                    ? null
                    : TextButton.icon(
                        onPressed: _retry,
                        icon: const SkinIcon(Icons.refresh, size: 18),
                        label: const Text('重试'),
                      ),
              ),
            TrpgComposer(
              guidePanel: TrpgPlayerGuideCard(
                session: _session,
                controller: _input,
                playerId: _session.players
                    .where((player) => !player.isAiControlled)
                    .firstOrNull
                    ?.playerId,
                actionEnabled: _composerMode == _SoloComposerMode.action,
                inputEnabled: !_sending,
              ),
              voiceButton: TrpgVoiceButton(
                controller: _input,
                settingsRepository: widget.settingsRepository,
                enabled: !_sending,
                onStart: () => _speech.stop(),
              ),
              toolsPanel: TrpgQuickActions(
                actions: [
                  TrpgActionSpec(
                    icon: Icons.lock_outline,
                    label: '私密频道',
                    onPressed: _showPrivateChannel,
                  ),
                  TrpgActionSpec(
                    icon: Icons.casino_outlined,
                    label: '私骰',
                    onPressed: _showPrivateDice,
                  ),
                  TrpgActionSpec(
                    icon: Icons.person_outline,
                    label: '角色',
                    onPressed: () => _showPanel('character'),
                  ),
                  TrpgActionSpec(
                    icon: Icons.backpack_outlined,
                    label: '背包',
                    onPressed: () => _showPanel('inventory'),
                  ),
                  TrpgActionSpec(
                    icon: Icons.assignment_outlined,
                    label: '任务',
                    onPressed: () => _showPanel('quests'),
                  ),
                  TrpgActionSpec(
                    icon: Icons.search,
                    label: '线索',
                    onPressed: () => _openImmersion(TrpgPanelType.clues),
                  ),
                  TrpgActionSpec(
                    icon: Icons.map_outlined,
                    label: '地图',
                    onPressed: () => _openImmersion(TrpgPanelType.map),
                  ),
                  TrpgActionSpec(
                    icon: Icons.casino_outlined,
                    label: '骰子说明',
                    onPressed: () => _showPanel('dice'),
                  ),
                  TrpgActionSpec(
                    icon: Icons.receipt_long_outlined,
                    label: '日志',
                    onPressed: () => _showPanel('log'),
                  ),
                ],
              ),
              controller: _input,
              hintText: switch (_composerMode) {
                _SoloComposerMode.action => '描述你的行动、对话或想法…',
                _SoloComposerMode.chat => '与 GM 和 AI 队友闲聊，不推进回合…',
                _SoloComposerMode.secret => '秘密行动，仅你与 GM 可见…',
              },
              onSend: _send,
              sending: _sending,
              modeSelector: Wrap(
                spacing: 7,
                runSpacing: 5,
                children: [
                  ChoiceChip(
                    avatar: const SkinIcon(
                      Icons.directions_run_outlined,
                      size: 16,
                    ),
                    selected: _composerMode == _SoloComposerMode.action,
                    onSelected: _sending
                        ? null
                        : (_) => setState(
                            () => _composerMode = _SoloComposerMode.action,
                          ),
                    label: const Text('行动'),
                  ),
                  ChoiceChip(
                    avatar: const SkinIcon(Icons.forum_outlined, size: 16),
                    selected: _composerMode == _SoloComposerMode.chat,
                    onSelected: _sending
                        ? null
                        : (_) => setState(
                            () => _composerMode = _SoloComposerMode.chat,
                          ),
                    label: const Text('闲聊'),
                  ),
                  ChoiceChip(
                    avatar: const SkinIcon(
                      Icons.visibility_off_outlined,
                      size: 16,
                    ),
                    selected: _composerMode == _SoloComposerMode.secret,
                    onSelected: _sending
                        ? null
                        : (_) => setState(
                            () => _composerMode = _SoloComposerMode.secret,
                          ),
                    label: const Text('秘密行动'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _timelineWidgets(String playerName) {
    final widgets = <Widget>[];
    for (final message in _session.chatHistory.where(
      (message) =>
          message.content.trim().isNotEmpty &&
          !(message.messageType == TRPGMessageType.gmMessage &&
              AIGMOutputGuard.looksLikeInternalAnalysis(message.content)),
    )) {
      widgets.add(
        _MessageCard(
          message: message,
          playerName: playerName,
          players: _session.players,
        ),
      );
    }
    for (final event in _session.eventLog.reversed.take(12).toList().reversed) {
      if (_eventCardTypes.contains(event.type) &&
          _eventVisibleToCurrentPlayer(event)) {
        widgets.add(_TRPGEventCard(event: event));
      }
    }
    final playerId = _session.players.firstOrNull?.playerId;
    if (playerId != null) {
      for (final resolution
          in _session.ruleState.privateResolutions
              .where((value) => value.visibleTo(playerId))
              .toList()
              .reversed
              .take(3)
              .toList()
              .reversed) {
        widgets.add(_PlayerResolutionCard(resolution: resolution));
      }
    }
    return widgets;
  }

  bool _eventVisibleToCurrentPlayer(TRPGEvent event) {
    final visibility = event.payload['visibility']?.toString();
    if (visibility == RollVisibility.gmHidden.name) return false;
    if (visibility != RollVisibility.playerPrivate.name) return true;
    final playerId = _session.players.firstOrNull?.playerId;
    final owners = (event.payload['visibilityPlayerIds'] as List? ?? const [])
        .map((value) => value.toString());
    return playerId != null && owners.contains(playerId);
  }

  static const _eventCardTypes = {
    TRPGEventType.diceRoll,
    TRPGEventType.skillCheck,
    TRPGEventType.itemGain,
    TRPGEventType.itemLoss,
    TRPGEventType.hpChange,
    TRPGEventType.questUpdate,
    TRPGEventType.sceneChange,
    TRPGEventType.clueDiscovered,
    TRPGEventType.combatStarted,
    TRPGEventType.damageApplied,
    TRPGEventType.combatEnded,
  };
}

class _PlayerResolutionCard extends StatelessWidget {
  const _PlayerResolutionCard({required this.resolution});

  final PlayerResolution resolution;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final private = resolution.visibility == ResolutionVisibility.playerPrivate;
    return Align(
      alignment: Alignment.center,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.secondaryContainer.withValues(alpha: .34),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.secondary.withValues(alpha: .38)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SkinIcon(
                  private ? Icons.lock_outline : Icons.groups_outlined,
                  size: 18,
                  color: colors.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    private ? '仅你可见 · ${resolution.title}' : resolution.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.secondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            for (final entry in resolution.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('• $entry'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.message,
    required this.playerName,
    required this.players,
  });
  final TRPGMessage message;
  final String playerName;
  final List<TRPGPlayer> players;

  @override
  Widget build(BuildContext context) {
    final label = switch (message.messageType) {
      TRPGMessageType.gmMessage => 'GM 主持',
      TRPGMessageType.npcMessage => 'NPC',
      TRPGMessageType.npcPlayerMessage =>
        players
                .where((player) => player.playerId == message.playerId)
                .firstOrNull
                ?.displayName ??
            'NPC玩家',
      TRPGMessageType.diceMessage => '骰子',
      TRPGMessageType.systemMessage => '系统',
      TRPGMessageType.playerMessage => playerName,
    };
    final tone = switch (message.messageType) {
      TRPGMessageType.gmMessage => TrpgMessageTone.gm,
      TRPGMessageType.npcMessage => TrpgMessageTone.npc,
      TRPGMessageType.npcPlayerMessage => TrpgMessageTone.player,
      TRPGMessageType.diceMessage => TrpgMessageTone.dice,
      TRPGMessageType.systemMessage => TrpgMessageTone.system,
      TRPGMessageType.playerMessage => TrpgMessageTone.player,
    };
    return TrpgMessageBubble(
      label: label,
      content: message.content,
      tone: tone,
      time: message.createdAt,
    );
  }
}

class _TRPGEventCard extends StatelessWidget {
  const _TRPGEventCard({required this.event});
  final TRPGEvent event;

  @override
  Widget build(BuildContext context) {
    final presentation = switch (event.type) {
      TRPGEventType.skillCheck => (
        Icons.fact_check_outlined,
        '技能检定',
        _skillText(event.payload),
      ),
      TRPGEventType.diceRoll => (
        Icons.casino_outlined,
        '骰子',
        _diceText(event.payload),
      ),
      TRPGEventType.itemGain => (
        Icons.add_box_outlined,
        '获得物品',
        _itemText(event.payload),
      ),
      TRPGEventType.itemLoss => (
        Icons.indeterminate_check_box_outlined,
        '失去物品',
        '${event.payload['itemId']} ×${event.payload['amount']}',
      ),
      TRPGEventType.hpChange => (
        Icons.favorite_outline,
        'HP 变化',
        '${event.payload['before']} → ${event.payload['after']}（${event.payload['reason']}）',
      ),
      TRPGEventType.questUpdate => (
        Icons.assignment_turned_in_outlined,
        '任务更新',
        '${event.payload['questId']} · ${event.payload['operation']}',
      ),
      TRPGEventType.sceneChange => (
        Icons.place_outlined,
        '场景变化',
        trpgEventPayloadLabel(event.payload['scene'], const [
          'title',
          'name',
          'id',
        ]),
      ),
      TRPGEventType.clueDiscovered => (
        Icons.search,
        '发现线索',
        trpgEventPayloadLabel(event.payload['clue'], const [
          'name',
          'title',
          'id',
        ]),
      ),
      TRPGEventType.combatStarted => (
        Icons.sports_martial_arts,
        '战斗开始',
        '先攻：${event.payload['initiative']}',
      ),
      TRPGEventType.combatEnded => (
        Icons.flag_outlined,
        '战斗结束',
        '${event.payload['reason']}',
      ),
      _ => (Icons.bolt_outlined, event.type.name, '${event.payload}'),
    };
    return TrpgEventTile(
      icon: presentation.$1,
      title: presentation.$2,
      details: presentation.$3,
    );
  }

  static String _skillText(Map<String, Object?> payload) {
    final explanation = payload['explanation']?.toString().trim();
    if (explanation != null && explanation.isNotEmpty) return explanation;
    final result = payload['result'];
    if (result is Map) {
      return ActionCheckResult.fromJson(
        result.cast<String, Object?>(),
      ).displayExplanation;
    }
    final chosen = payload['chosenRoll'];
    final modifier = (payload['modifier'] as num?)?.toInt() ?? 0;
    final critical = payload['criticalSuccess'] == true
        ? '大成功'
        : payload['criticalFailure'] == true
        ? '大失败'
        : payload['success'] == true
        ? '成功'
        : '失败';
    return '${payload['stat']} · D20 $chosen '
        '${modifier >= 0 ? '+' : ''}$modifier = ${payload['total']} / DC ${payload['difficulty']} · $critical';
  }

  static String _diceText(Map<String, Object?> payload) =>
      '${payload['diceType']} ${payload['individualResults'] ?? payload['rolls']} = ${payload['finalResult'] ?? payload['total']} · ${payload['reason'] ?? 'manual_roll'}';

  static String _itemText(Map<String, Object?> payload) {
    final item = payload['item'] as Map?;
    return '${item?['name'] ?? item?['id'] ?? ''} ×${item?['quantity'] ?? 1}';
  }
}
