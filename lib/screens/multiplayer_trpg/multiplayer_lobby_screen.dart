// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:convert';
import '../trpg_shared/trpg_voice_button.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/skins/theme_background.dart';
import '../../app/skins/theme_tokens.dart';
import '../app_settings/skin_gallery_page.dart';
import 'package:uuid/uuid.dart';

import '../../models/api_profile.dart';
import '../../models/multiplayer_models.dart';
import '../../models/nearby_models.dart';
import '../../models/social_models.dart';
import '../../models/trpg_models.dart';
import '../../models/trpg_gameplay_models.dart';
import '../../models/trpg_presentation_models.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/trpg_session_repository.dart';
import '../../services/ai_service.dart';
import '../../services/trpg/ai_gm_output_guard.dart';
import '../../services/trpg/client_ai_host_service.dart';
import '../../services/trpg/multiplayer_transport.dart';
import '../../services/trpg/nearby_host_bridge.dart';
import '../../services/trpg/trpg_presentation_service.dart';
import '../trpg_shared/trpg_immersion_panel.dart';
import '../trpg_shared/trpg_presentation_stage.dart';
import '../trpg_shared/trpg_memory_screen.dart';
import '../trpg_shared/trpg_play_ui.dart';
import '../trpg_shared/trpg_player_guide_card.dart';
import '../trpg_shared/trpg_private_mailbox_screen.dart';

class MultiplayerLobbyScreen extends StatefulWidget {
  const MultiplayerLobbyScreen({
    required this.initialSnapshot,
    required this.client,
    required this.apiRepository,
    required this.aiService,
    required this.repository,
    required this.settingsRepository,
    this.nearbyHostBridge,
    super.key,
  });
  final MultiplayerSnapshot initialSnapshot;
  final MultiplayerClient client;
  final ApiRepository apiRepository;
  final AiService aiService;
  final TRPGSessionRepository repository;
  final SettingsRepository settingsRepository;
  final NearbyHostBridge? nearbyHostBridge;

  @override
  State<MultiplayerLobbyScreen> createState() => _MultiplayerLobbyScreenState();
}

class _MultiplayerLobbyScreenState extends State<MultiplayerLobbyScreen> {
  late MultiplayerSnapshot _snapshot;
  late final ClientAIHostService _hostService;
  StreamSubscription<MultiplayerSnapshot>? _stateSub;
  StreamSubscription<MultiplayerEnvelope>? _eventSub;
  StreamSubscription? _nearbyVerificationSub;
  StreamSubscription? _nearbyNoticeSub;
  Timer? _credentialSave;
  Timer? _draftSave;
  Timer? _countdownTicker;
  DateTime? _settlementWaitingSince;
  DateTime? _lastSettlementRetry;
  String? _waitingTurnId;
  List<ApiProfile> _profiles = const [];
  String? _profileId;
  final _action = TextEditingController();
  bool _chatMode = false;
  bool _secretMode = false;
  bool _testing = false;
  bool? _showPresentationStage;
  final Set<String> _unreadPrivateContactIds = {};
  String? _notice;
  bool _allowExit = false;
  bool _exitPromptOpen = false;

  Future<void> _copyWebInvite() async {
    final code = _room.roomCode;
    if (_isNearby || !RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code)) return;
    await Clipboard.setData(
      ClipboardData(text: 'https://ai-tavern-cloud.pages.dev/join/$code'),
    );
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网页邀请已复制；网页同步公开房间状态，不公开私聊内容')),
      );
  }

  Future<bool> _saveLocal() async {
    final session = _session;
    if (session == null) return false;
    try {
      final raw = session.toJson();
      raw['id'] = 'multiplayer-${_room.roomId}-$_myId';
      raw['metadata'] = {
        ...session.metadata,
        'localMultiplayerArchive': true,
        'localPlayerId': _myId,
        'sourceRoomId': _room.roomId,
        'sourceRevision': _room.revision,
        'savedRoom': _room.toJson(),
      };
      raw['updatedAt'] = DateTime.now().toIso8601String();
      await widget.repository.upsert(TRPGSession.fromJson(raw));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存本地，可在多人首页的本地存档中查看或转为单人')),
        );
      return true;
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      return false;
    }
  }

  Future<void> _confirmExit() async {
    if (_exitPromptOpen) return;
    _exitPromptOpen = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出多人跑团？'),
        content: const Text('退出会断开本机连接；如果你正在提供 AI 主持，其他玩家的结算可能暂停。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续游玩'),
          ),
          if (_session != null)
            TextButton(
              onPressed: () async {
                if (await _saveLocal() && context.mounted)
                  Navigator.pop(context, true);
              },
              child: const Text('保存并退出'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
    _exitPromptOpen = false;
    if (leave != true || !mounted) return;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  late final TRPGPresentationService _presentation;
  late final ValueNotifier<List<TRPGPrivateMessage>> _privateMessageListenable;

  String get _myId => widget.client.credentials!.playerId;
  TRPGRoom get _room => _snapshot.room;
  TRPGSession? get _session => _snapshot.session;
  bool get _isOwner => _room.ownerPlayerId == _myId;
  CampaignMemberRole? get _campaignRole => _room.campaignMemberRoles[_myId];
  bool get _canManagePersistent =>
      _room.kind == CampaignRoomKind.persistent &&
      const {
        CampaignMemberRole.owner,
        CampaignMemberRole.admin,
        CampaignMemberRole.humanGm,
      }.contains(_campaignRole);
  bool get _canManage => _isOwner || _canManagePersistent;
  bool get _isHost => _room.aiHostConfig.providerPlayerId == _myId;
  bool get _isNearby =>
      widget.nearbyHostBridge != null ||
      (widget.client.credentials?.endpoint.startsWith('nearby:') ?? false);
  TRPGPlayer get _me => _room.players.firstWhere((p) => p.playerId == _myId);

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialSnapshot;
    _privateMessageListenable = ValueNotifier(
      widget.initialSnapshot.session?.immersionState.privateMessages ??
          const [],
    );
    _presentation = TRPGPresentationService(
      initialState:
          widget.initialSnapshot.session?.presentationState ??
          const CurrentPresentationState(),
    );
    _hostService = ClientAIHostService(
      client: widget.client,
      apiRepository: widget.apiRepository,
      aiService: AiService(),
    );
    _stateSub = widget.client.states.listen(_onState);
    _eventSub = widget.client.events.listen(_onEvent);
    final nearbyHost = widget.nearbyHostBridge;
    if (nearbyHost != null) {
      _nearbyVerificationSub = nearbyHost.verificationRequests.listen(
        (request) => _showNearbyVerification(request),
      );
      _nearbyNoticeSub = nearbyHost.connectionNotices.listen((notice) {
        if (mounted) setState(() => _notice = notice);
      });
    }
    _loadProfiles();
    _action.addListener(_scheduleDraftSave);
    unawaited(_restoreTurnDraft());
    _syncCountdownTicker();
  }

  MultiplayerTurn? get _turn => _room.currentTurn;
  PlayerTurnAction? get _myTurnAction => _turn?.playerActions[_myId];
  bool get _myTurnConfirmed => _myTurnAction?.confirmed == true;

  int? get _settlementSeconds {
    final turn = _turn;
    final deadline = turn?.settlementDeadline;
    if (turn?.phase != MultiplayerTurnPhase.collecting ||
        deadline == null ||
        turn?.allConfirmed != true) {
      return null;
    }
    final milliseconds = deadline.difference(DateTime.now()).inMilliseconds;
    return ((milliseconds.clamp(0, 5000) + 999) ~/ 1000).clamp(0, 5);
  }

  void _syncCountdownTicker() {
    final busy = _room.aiHostConfig.status == AIHostStatus.busy;
    if (busy &&
        (_settlementWaitingSince == null || _waitingTurnId != _turn?.turnId)) {
      _settlementWaitingSince = DateTime.now();
      _waitingTurnId = _turn?.turnId;
    } else if (!busy) {
      _settlementWaitingSince = null;
      _waitingTurnId = null;
    }
    final shouldTick =
        _settlementSeconds != null ||
        busy ||
        (_lastSettlementRetry != null &&
            DateTime.now().difference(_lastSettlementRetry!).inSeconds < 5);
    if (!shouldTick) {
      _countdownTicker?.cancel();
      _countdownTicker = null;
      return;
    }
    _countdownTicker ??= Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _retrySettlement() async {
    if (!_isOwner ||
        (_lastSettlementRetry != null &&
            DateTime.now().difference(_lastSettlementRetry!).inSeconds < 5))
      return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新请求本回合结算？'),
        content: const Text('玩家行动和已完成的规则结果会保留。旧请求的迟到回复将被忽略；新的模型请求可能产生 API 费用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续等待'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重试结算'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _lastSettlementRetry = DateTime.now();
      _settlementWaitingSince = DateTime.now();
      _notice = '已请求重新结算，玩家行动保留。';
    });
    _syncCountdownTicker();
    try {
      await widget.client.retryAction();
    } catch (_) {
      if (mounted) setState(() => _notice = '重试请求未能发送，请检查房间连接。');
    }
  }

  void _scheduleDraftSave() {
    if (_chatMode || _myTurnConfirmed) return;
    _draftSave?.cancel();
    _draftSave = Timer(const Duration(milliseconds: 350), () {
      final turn = _turn;
      if (turn == null) return;
      widget.apiRepository.writeMultiplayerTurnDraft(
        _room.roomId,
        _myId,
        jsonEncode({
          'turnId': turn.turnId,
          'content': _action.text,
          'secret': _secretMode,
        }),
      );
    });
  }

  Future<void> _restoreTurnDraft() async {
    final turn = _turn;
    if (turn == null) return;
    final confirmed = turn.playerActions[_myId];
    if (confirmed?.confirmed == true) {
      _action.text = confirmed!.content;
      _secretMode = confirmed.metadata['secret'] == true;
      return;
    }
    final raw = await widget.apiRepository.readMultiplayerTurnDraft(
      _room.roomId,
      _myId,
    );
    if (raw.isEmpty || !mounted) return;
    try {
      final value = (jsonDecode(raw) as Map).cast<String, Object?>();
      if (value['turnId'] != turn.turnId) return;
      setState(() {
        _action.text = value['content'] as String? ?? '';
        _secretMode = value['secret'] == true;
        _chatMode = false;
      });
    } catch (_) {}
  }

  Future<void> _loadProfiles() async {
    final profiles = await widget.apiRepository.getAll();
    if (!mounted) return;
    final matching = profiles
        .where((profile) => profile.model == _room.aiHostConfig.modelId)
        .toList();
    final resumeProfile =
        _isHost &&
            matching.length == 1 &&
            const {
              AIHostStatus.ready,
              AIHostStatus.busy,
              AIHostStatus.error,
            }.contains(_room.aiHostConfig.status)
        ? matching.single
        : null;
    setState(() {
      _profiles = profiles;
      _profileId = resumeProfile?.id ?? profiles.firstOrNull?.id;
    });
    if (resumeProfile != null) {
      try {
        await _hostService.activate(resumeProfile);
        await widget.client.acceptHost(modelId: resumeProfile.model);
      } catch (_) {
        if (mounted) setState(() => _notice = '主持连接恢复失败，请重新指定 AI Host。');
      }
    }
    if (_room.kind == CampaignRoomKind.persistent) {
      await widget.client.sendDeviceCapability(
        supportsAIHost: profiles.isNotEmpty,
        providerTypes: profiles.map((value) => value.apiType).toSet().toList(),
        toolCallingVerified: false,
      );
    }
  }

  void _onState(MultiplayerSnapshot value) {
    if (!mounted) return;
    final wasHost = _isHost;
    final priorTurnId = _snapshot.room.currentTurn?.turnId;
    final oldPrivateIds =
        _snapshot.session?.immersionState.privateMessages
            .map((message) => message.id)
            .toSet() ??
        const <String>{};
    final incoming = value.session?.immersionState.privateMessages
        .where(
          (message) =>
              !oldPrivateIds.contains(message.id) && message.senderId != _myId,
        )
        .lastOrNull;
    setState(() {
      _snapshot = value;
      if (incoming != null) {
        _unreadPrivateContactIds.add(_privateConversationId(incoming));
      }
    });
    _privateMessageListenable.value =
        value.session?.immersionState.privateMessages ?? const [];
    if (wasHost && !_isHost) unawaited(_hostService.dispose());
    _syncCountdownTicker();
    if (incoming != null) {
      final sender = _resolvePrivateName(incoming.senderId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('收到 $sender 的新私信'),
          action: SnackBarAction(
            label: '查看',
            onPressed: () => unawaited(_showPrivateChannel()),
          ),
        ),
      );
    }
    if (value.room.currentTurn?.turnId != priorTurnId) {
      _action.clear();
      unawaited(_restoreTurnDraft());
    }
    final nearbyHost = widget.nearbyHostBridge;
    if (nearbyHost != null) {
      final owner = value.room.players
          .where((player) => player.playerId == value.room.ownerPlayerId)
          .firstOrNull;
      unawaited(
        nearbyHost.updateAdvertisement(
          NearbyRoomAdvertisement(
            endpointId: '',
            roomId: value.room.roomId,
            roomCode: value.room.roomCode,
            roomName: value.room.roomName,
            ownerName: owner?.displayName ?? '房主',
            currentPlayers: value.room.players.length,
            maxPlayers: value.room.maxPlayers,
          ),
        ),
      );
    }
    final state = value.session?.presentationState;
    if (state != null &&
        state.sequenceNumber >= _presentation.state.sequenceNumber) {
      _presentation.restore(state);
    }
    _credentialSave?.cancel();
    _credentialSave = Timer(const Duration(milliseconds: 250), () {
      final credentials = widget.client.credentials;
      if (credentials != null) {
        widget.apiRepository.writeMultiplayerCredentials(
          jsonEncode(credentials.toJson()),
        );
      }
    });
  }

  Future<void> _showNearbyVerification(
    NearbyVerificationRequest request,
  ) async {
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('确认附近玩家'),
        content: Text(
          '${request.endpointName} 请求加入。请与对方当面核对两台设备显示的数字：\n\n'
          '${request.authenticationDigits}\n\n数字一致才允许连接。',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('数字一致，允许'),
          ),
        ],
      ),
    );
    final bridge = widget.nearbyHostBridge;
    if (bridge == null) return;
    if (accepted == true) {
      await bridge.accept(request.endpointId);
    } else {
      await bridge.reject(request.endpointId);
    }
  }

  void _onEvent(MultiplayerEnvelope event) {
    if (!mounted) return;
    if (event.type == MultiplayerEventType.hostRequested &&
        event.payload['providerPlayerId'] == _myId) {
      _showHostRequest();
    }
    if (event.type == MultiplayerEventType.error) {
      setState(
        () => _notice = event.payload['message']?.toString() ?? '服务器拒绝了操作',
      );
    }
    if (event.type == MultiplayerEventType.presentationEvent &&
        event.payload['event'] is Map) {
      unawaited(
        _presentation.enqueue(
          PresentationEvent.fromJson(
            (event.payload['event'] as Map).cast<String, Object?>(),
          ),
        ),
      );
    }
  }

  Future<void> _showHostRequest() async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('AI 主持模型请求'),
        content: Text(
          '房主希望使用你的 AI 模型作为本局主持人。\n\n模型：${_room.aiHostConfig.modelId ?? '由你选择'}\n\n你的 API Key 只在本机使用，不会发送给服务器、房主或其他玩家。主持服务会收到本局剧情与玩家行动。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: _profiles.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('选择模型并同意'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _acceptHost();
    } else {
      await widget.client.declineHost();
    }
  }

  ApiProfile? get _profile =>
      _profiles.where((p) => p.id == _profileId).firstOrNull;

  Future<void> _acceptHost() async {
    final profile = _profile;
    if (profile == null) {
      setState(() => _notice = '请先在应用设置中添加 AI API 配置');
      return;
    }
    setState(() => _testing = true);
    try {
      final supported = await _hostService.testToolCalling(profile);
      if (!supported) throw StateError('当前模型不支持跑团主持所需的工具调用');
      await widget.client.sendDeviceCapability(
        supportsAIHost: true,
        providerTypes: [profile.apiType],
        toolCallingVerified: true,
      );
      await _hostService.activate(profile);
      await widget.client.acceptHost(modelId: profile.model);
      if (mounted) setState(() => _notice = '主持模型连接测试通过，已成为本局 API Host。');
    } catch (error) {
      if (mounted) setState(() => _notice = '模型测试失败：$error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _chooseCharacter() async {
    final name = TextEditingController(text: '${_me.displayName}的角色');
    final background = TextEditingController(text: '来到雾港追查失踪调查员的冒险者。');
    final result = await showDialog<PlayerCharacter>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建多人角色'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '角色名'),
              ),
              TextField(
                controller: background,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '背景'),
              ),
              const SizedBox(height: 12),
              const Text(
                '初始属性：STR 10 / DEX 12 / INT 12 / PER 12 / CHA 10，HP 20',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              PlayerCharacter(
                id: const Uuid().v4(),
                playerId: _myId,
                name: name.text.trim().isEmpty ? '无名冒险者' : name.text.trim(),
                background: background.text.trim(),
                stats: const {
                  'STR': 10,
                  'DEX': 12,
                  'INT': 12,
                  'PER': 12,
                  'CHA': 10,
                },
                skills: const {
                  'perception': 2,
                  'investigation': 2,
                  'stealth': 0,
                },
              ),
            ),
            child: const Text('使用角色'),
          ),
        ],
      ),
    );
    name.dispose();
    background.dispose();
    if (result != null) await widget.client.selectCharacter(result);
  }

  Future<void> _pickHost() async {
    final selected = await showModalBottomSheet<TRPGPlayer>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('指定 AI API Host'),
              subtitle: Text('房主与模型提供者互相独立；对方必须确认。'),
            ),
            ..._room.players
                .where((p) => p.connectionStatus == TRPGConnectionStatus.online)
                .map(
                  (player) => ListTile(
                    onTap: () => Navigator.pop(context, player),
                    leading: const Icon(Icons.person_outline),
                    title: Text(player.displayName),
                    subtitle: Text(
                      player.playerId == _room.ownerPlayerId
                          ? '房主（也可以提供 API）'
                          : '玩家',
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await widget.client.requestHost(
        selected.playerId,
        modelId: selected.playerId == _myId ? _profile?.model : null,
      );
      if (selected.playerId == _myId) await _showHostRequest();
    }
  }

  Future<void> _send() async {
    final content = _action.text.trim();
    if (_chatMode) {
      if (content.isEmpty) return;
      _action.clear();
      await widget.client.submitChat(content);
      return;
    }
    final turn = _turn;
    if (_me.role == TRPGPlayerRole.humanGm &&
        turn?.phase == MultiplayerTurnPhase.gmResponding) {
      if (content.isEmpty) return;
      _action.clear();
      await widget.client.resolveHumanGmTurn(turn!.turnId, content);
      return;
    }
    if (_session?.ruleState.combatActive == true ||
        turn?.mode == MultiplayerTurnMode.combatInitiative) {
      if (content.isEmpty) return;
      _action.clear();
      if (_secretMode) {
        await widget.client.submitSecretAction(content);
      } else {
        await widget.client.submitAction(content);
      }
      return;
    }
    if (turn == null || turn.phase != MultiplayerTurnPhase.collecting) return;
    await widget.client.confirmTurnAction(
      turnId: turn.turnId,
      content: content,
      secret: _secretMode,
    );
    await widget.apiRepository.writeMultiplayerTurnDraft(
      _room.roomId,
      _myId,
      '',
    );
  }

  Future<void> _modifyTurnAction() async {
    final turn = _turn;
    if (turn == null) return;
    final draft = _myTurnAction?.content ?? _action.text;
    final secret = _myTurnAction?.metadata['secret'] == true || _secretMode;
    await widget.client.unconfirmTurnAction(turn.turnId);
    if (!mounted) return;
    setState(() {
      _action.text = draft;
      _secretMode = secret;
    });
  }

  Future<void> _skipPlayerThisTurn(String playerId) async {
    final turn = _turn;
    if (turn == null) return;
    await widget.client.skipTurnPlayer(turn.turnId, playerId);
  }

  Widget _turnCollectionCard() {
    final turn = _turn;
    if (turn == null || turn.mode != MultiplayerTurnMode.freeformGroup) {
      return const SizedBox.shrink();
    }
    final expected = turn.expectedPlayerIds
        .map(
          (id) => _room.players
              .where((player) => player.playerId == id)
              .firstOrNull,
        )
        .whereType<TRPGPlayer>()
        .toList();
    final collecting = turn.phase == MultiplayerTurnPhase.collecting;
    final isHumanGm = _me.role == TRPGPlayerRole.humanGm;
    final waiting = expected
        .where((player) => !turn.confirmedPlayerIds.contains(player.playerId))
        .toList();
    final countdown = _settlementSeconds;
    final status = switch (turn.phase) {
      MultiplayerTurnPhase.collecting =>
        countdown == null
            ? '已确认 ${turn.confirmedPlayerIds.length} / ${turn.expectedPlayerIds.length}'
            : '$countdown 秒后开始结算，可撤回修改',
      MultiplayerTurnPhase.resolving ||
      MultiplayerTurnPhase.gmResponding ||
      MultiplayerTurnPhase.applyingTools => '所有玩家已确认，主持人正在统一结算……',
      MultiplayerTurnPhase.completed => '本回合已完成',
      MultiplayerTurnPhase.cancelled => '本回合已取消',
    };
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '行动轮次 ${turn.roundNumber}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(status),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: expected.map((player) {
                final action = turn.playerActions[player.playerId];
                final confirmed = action?.confirmed == true;
                final offline =
                    player.connectionStatus != TRPGConnectionStatus.online;
                return ActionChip(
                  avatar: Icon(
                    confirmed
                        ? action!.isPass
                              ? Icons.skip_next
                              : Icons.check_circle
                        : offline
                        ? Icons.cloud_off
                        : Icons.more_horiz,
                    size: 17,
                  ),
                  label: Text(
                    '${player.displayName} · ${confirmed ? (action!.isPass ? '跳过' : '已确认') : (offline ? '已掉线' : '思考中')}',
                  ),
                  onPressed: _canManage && collecting && offline && !confirmed
                      ? () => _skipPlayerThisTurn(player.playerId)
                      : null,
                );
              }).toList(),
            ),
            if (!isHumanGm && _myTurnConfirmed) ...[
              const SizedBox(height: 8),
              Text(
                _myTurnAction!.isPass
                    ? '✓ 你已确认：本回合保持观察'
                    : '✓ 你的行动：${_myTurnAction!.content}',
              ),
            ],
            if (waiting.isNotEmpty && !isHumanGm) ...[
              const SizedBox(height: 4),
              Text('等待：${waiting.map((value) => value.displayName).join('、')}'),
            ],
            if (!isHumanGm && collecting) ...[
              const SizedBox(height: 10),
              if (_myTurnConfirmed)
                OutlinedButton.icon(
                  onPressed: _modifyTurnAction,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('修改行动'),
                )
              else
                FilledButton.icon(
                  onPressed: _send,
                  icon: const Icon(Icons.check),
                  label: Text(contentOrPassLabel),
                ),
            ],
            if (isHumanGm &&
                turn.phase == MultiplayerTurnPhase.gmResponding) ...[
              const Divider(height: 20),
              ...turn.expectedPlayerIds.map((playerId) {
                final action = turn.playerActions[playerId];
                if (action == null) return const SizedBox.shrink();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${action.playerDisplayName} · ${action.characterName}',
                  ),
                  subtitle: Text(action.isPass ? '本回合跳过' : action.content),
                );
              }),
              const Text('所有行动已锁定。请在下方输入本回合主持叙事并结算。'),
            ],
          ],
        ),
      ),
    );
  }

  String get contentOrPassLabel =>
      _action.text.trim().isEmpty ? '确认本回合（跳过）' : '确认本回合';

  String _resolvePrivateName(String senderId) {
    if (senderId == 'gm') return 'GM 主持';
    if (senderId == 'system') return '私密系统';
    return _room.players
            .where((player) => player.playerId == senderId)
            .firstOrNull
            ?.displayName ??
        '未知联系人';
  }

  String _privateConversationId(TRPGPrivateMessage message) {
    final humanGm = _room.players
        .where((player) => player.role == TRPGPlayerRole.humanGm)
        .firstOrNull;
    if (_me.role == TRPGPlayerRole.humanGm) {
      if (message.senderId != _myId &&
          message.senderId != 'gm' &&
          message.senderId != 'system') {
        return message.senderId;
      }
      return message.recipientIds.firstWhere(
        (id) => id != _myId,
        orElse: () => 'gm',
      );
    }
    if (message.toGm ||
        message.senderId == 'gm' ||
        message.senderId == 'system' ||
        message.senderId == humanGm?.playerId) {
      return 'gm';
    }
    return message.senderId == _myId
        ? message.recipientIds.firstWhere(
            (id) => id != _myId,
            orElse: () => 'gm',
          )
        : message.senderId;
  }

  List<TrpgPrivateContact> _privateContacts() {
    final humanGm = _room.players
        .where((player) => player.role == TRPGPlayerRole.humanGm)
        .firstOrNull;
    final contacts = <TrpgPrivateContact>[];
    if (_me.role != TRPGPlayerRole.humanGm) {
      contacts.add(
        TrpgPrivateContact(
          id: 'gm',
          name: humanGm?.displayName ?? 'GM 主持',
          subtitle: humanGm == null ? 'AI 主持与规则裁定' : '真人主持',
          aliasIds: [if (humanGm != null) humanGm.playerId],
          isGm: true,
        ),
      );
    }
    for (final player in _room.players.where(
      (player) =>
          player.playerId != _myId &&
          !(_me.role != TRPGPlayerRole.humanGm &&
              player.playerId == humanGm?.playerId),
    )) {
      contacts.add(
        TrpgPrivateContact(
          id: player.playerId,
          name: player.displayName,
          subtitle: player.connectionStatus == TRPGConnectionStatus.online
              ? '在线'
              : '离线',
        ),
      );
    }
    return contacts;
  }

  Future<List<TRPGPrivateMessage>?> _sendPrivateToContact(
    TrpgPrivateContact target,
    String content,
  ) async {
    final before = _session?.immersionState.privateMessages ?? const [];
    await widget.client.sendPrivateMessage(
      content,
      toGm: target.isGm,
      recipientPlayerIds: target.isGm ? const [] : [target.id],
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final refreshed = _session?.immersionState.privateMessages ?? before;
    if (refreshed.length != before.length) return refreshed;
    return null;
  }

  Future<void> _showPrivateChannel() async {
    final session = _session;
    if (session == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TrpgPrivateMailboxScreen(
          currentPlayerId: _myId,
          contacts: _privateContacts(),
          messages: session.immersionState.privateMessages,
          resolveName: _resolvePrivateName,
          onSend: _sendPrivateToContact,
          messageListenable: _privateMessageListenable,
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
        icon: const Icon(Icons.casino_outlined),
        title: const Text('服务器私密投骰'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('点数只由房主服务器生成，仅你与 GM 可以看到。'),
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
            child: const Text('请求投骰'),
          ),
        ],
      ),
    );
    final formulaText = formula.text.trim();
    final reasonText = reason.text.trim();
    formula.dispose();
    reason.dispose();
    if (confirmed != true || formulaText.isEmpty) return;
    await widget.client.privateRoll(formula: formulaText, reason: reasonText);
  }

  Future<void> _openPanel(TrpgPanelType type) async {
    final session = _session;
    if (session == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TrpgImmersionPanel(
          session: session,
          type: type,
          playerId: _myId,
          isGm: _me.role == TRPGPlayerRole.humanGm,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _credentialSave?.cancel();
    _draftSave?.cancel();
    _countdownTicker?.cancel();
    _stateSub?.cancel();
    _eventSub?.cancel();
    _nearbyVerificationSub?.cancel();
    _nearbyNoticeSub?.cancel();
    _hostService.dispose();
    _privateMessageListenable.dispose();
    _presentation.dispose();
    widget.client.close();
    final nearbyHost = widget.nearbyHostBridge;
    if (nearbyHost != null) unawaited(nearbyHost.close());
    _action.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_confirmExit());
      },
      child: _room.status == MultiplayerRoomStatus.lobby
          ? _buildLobby(context)
          : _buildGame(context),
    );
  }

  Widget _buildLobby(BuildContext context) {
    final participatingPlayers = _room.players.where(
      (player) => player.role != TRPGPlayerRole.humanGm,
    );
    final allReady =
        participatingPlayers.isNotEmpty &&
        participatingPlayers.every(
          (player) => player.isReady && player.characterId != null,
        );
    final hostReady =
        _room.gmMode == AIHostMode.humanGm ||
        _room.aiHostConfig.status == AIHostStatus.ready;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNearby ? '附近联机 Lobby' : '多人跑团 Lobby'),
        actions: [
          if (!_isNearby)
            IconButton(
              onPressed: _copyWebInvite,
              tooltip: '复制网页联机邀请',
              icon: const Icon(Icons.link),
            ),
          IconButton(
            tooltip: '外观与皮肤',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () =>
                openSkinGallery(context, contextHint: _room.campaignId),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _room.roomName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (_isNearby)
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: const ListTile(
                    leading: Icon(Icons.wifi_tethering),
                    title: Text('附近房间正在广播'),
                    subtitle: Text(
                      '另一台手机请进入“附近联机”并点击“搜索房间”。不要把内部房间码填进互联网/局域网页面。',
                    ),
                  ),
                )
              else
                SelectableText(
                  '房间码：${_room.roomCode}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              Text('剧本：${_room.campaignId} · 规则：${_room.ruleSystemId}'),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.groups),
                      title: Text('房间玩家'),
                    ),
                    ..._room.players.map(
                      (player) => ListTile(
                        leading: CircleAvatar(
                          child: Text(player.displayName.characters.first),
                        ),
                        title: Row(
                          children: [
                            Flexible(child: Text(player.displayName)),
                            if (player.playerId == _room.ownerPlayerId)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Chip(label: Text('房主')),
                              ),
                            if (player.playerId ==
                                _room.aiHostConfig.providerPlayerId)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Chip(
                                  avatar: Icon(Icons.cloud, size: 16),
                                  label: Text('API Host'),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '${player.connectionStatus.name} · ${player.characterId == null ? '未选择角色' : '角色已锁定'}',
                        ),
                        trailing: Icon(
                          player.isReady
                              ? Icons.check_circle
                              : Icons.hourglass_empty,
                          color: player.isReady
                              ? ThemeTokens.of(context).success
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.smart_toy_outlined),
                      title: Text('AI 主持'),
                    ),
                    if (_profiles.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: _profileId,
                        decoration: const InputDecoration(
                          labelText: '我本机可提供的模型',
                        ),
                        items: _profiles
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text('${p.name} · ${p.model}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _profileId = value),
                      ),
                    ListTile(
                      title: Text(_room.aiHostConfig.modelId ?? '等待房主指定提供者'),
                      subtitle: Text(
                        '状态：${_room.aiHostConfig.status.name}\n'
                        'API Key 不会离开提供者设备'
                        '${_isHost ? '\n请求 ${_room.aiHostConfig.requestCount} · Token ${_room.aiHostConfig.inputTokens + _room.aiHostConfig.outputTokens} · 错误 ${_room.aiHostConfig.errorCount}' : ''}',
                      ),
                      trailing: _canManage
                          ? TextButton(
                              onPressed: _pickHost,
                              child: const Text('选择提供者'),
                            )
                          : null,
                    ),
                    if (_isHost &&
                        _room.aiHostConfig.status != AIHostStatus.ready)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: FilledButton.icon(
                          onPressed: _testing ? null : _acceptHost,
                          icon: const Icon(Icons.cloud_done),
                          label: Text(
                            _testing ? '正在验证 Tool Calling…' : '测试模型并接受主持',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _chooseCharacter,
                      icon: const Icon(Icons.badge_outlined),
                      label: Text(_me.characterId == null ? '选择/创建角色' : '更换角色'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _me.characterId == null
                          ? null
                          : () => widget.client.setReady(!_me.isReady),
                      icon: Icon(_me.isReady ? Icons.undo : Icons.check),
                      label: Text(_me.isReady ? '取消 Ready' : 'Ready'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _canManage && allReady && hostReady
                    ? widget.client.startGame
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  !_canManage
                      ? '等待 Owner / Admin / GM 开始'
                      : !allReady
                      ? '等待所有玩家 Ready 并选择角色'
                      : !hostReady
                      ? '等待 AI Host 就绪'
                      : '开始游戏',
                ),
              ),
              if (_notice != null) _noticeCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGame(BuildContext context) {
    final session = _session;
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final showPresentationStage = _showPresentationStage ?? false;
    final myCharacter = session?.playerCharacters
        .where((value) => value.playerId == _myId)
        .firstOrNull;
    final processing = _room.aiHostConfig.status == AIHostStatus.busy;
    final paused =
        _room.status == MultiplayerRoomStatus.paused || _room.gmWaiting;
    final turn = _turn;
    final isGroupTurn = turn?.mode == MultiplayerTurnMode.freeformGroup;
    final humanGmCanResolve =
        _me.role == TRPGPlayerRole.humanGm &&
        turn?.phase == MultiplayerTurnPhase.gmResponding;
    final canEditGroupAction =
        isGroupTurn &&
        turn?.phase == MultiplayerTurnPhase.collecting &&
        !_myTurnConfirmed;
    final composerEnabled =
        !paused &&
        (_chatMode ||
            humanGmCanResolve ||
            session?.ruleState.combatActive == true ||
            !isGroupTurn ||
            canEditGroupAction);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isNarrow ? 58 : 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_room.roomName),
            Text(
              '${_room.players.where((p) => p.connectionStatus == TRPGConnectionStatus.online).length} 人在线 · rev ${_room.revision}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _saveLocal,
            tooltip: '保存本地',
            icon: const Icon(Icons.save_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'webInvite') _copyWebInvite();
              if (value == 'clues') _openPanel(TrpgPanelType.clues);
              if (value == 'skin') {
                unawaited(
                  openSkinGallery(
                    context,
                    contextHint: session?.title ?? _room.campaignId,
                  ),
                );
              }
              if (value == 'map') _openPanel(TrpgPanelType.map);
              if (value == 'people') _openPanel(TrpgPanelType.people);
              if (value == 'timeline') _openPanel(TrpgPanelType.timeline);
              if (value == 'recap') _openPanel(TrpgPanelType.recap);
              if (value == 'memory' && session != null) {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TRPGMemoryScreen(
                      session: session,
                      playerId: _myId,
                      isGm: _me.role == TRPGPlayerRole.humanGm,
                      canEdit: false,
                      onChanged: (_) {},
                    ),
                  ),
                );
              }
              if (value == 'gm') _openPanel(TrpgPanelType.gm);
              if (value == 'private') _showPrivateChannel();
              if (value == 'roll') unawaited(_showPrivateDice());
            },
            itemBuilder: (_) => [
              if (!_isNearby)
                const PopupMenuItem(
                  value: 'webInvite',
                  child: Text('复制网页邀请 / 状态同步'),
                ),
              const PopupMenuItem(value: 'clues', child: Text('线索板')),
              const PopupMenuItem(value: 'skin', child: Text('外观与皮肤')),
              const PopupMenuItem(value: 'map', child: Text('地图')),
              const PopupMenuItem(value: 'people', child: Text('人物')),
              const PopupMenuItem(value: 'timeline', child: Text('Timeline')),
              const PopupMenuItem(value: 'memory', child: Text('冒险记录 / 长期记忆')),
              const PopupMenuItem(value: 'recap', child: Text('上次发生了什么？')),
              const PopupMenuItem(value: 'private', child: Text('私聊频道')),
              const PopupMenuItem(value: 'roll', child: Text('服务器私密投骰')),
              if (_me.role == TRPGPlayerRole.humanGm)
                const PopupMenuItem(value: 'gm', child: Text('GM Panel')),
            ],
          ),
          IconButton(
            onPressed: () => _showPlayers(context),
            icon: const Icon(Icons.groups),
          ),
        ],
      ),
      body: ThemeBackground(
        chat: true,
        child: Column(
          children: [
            if (session != null && showPresentationStage)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: TRPGPresentationStage(
                  session: session,
                  service: _presentation,
                  compact: true,
                  onReplayVoice: (_) {},
                  onSkip: _presentation.skip,
                ),
              ),
            if (paused)
              TrpgInlineNotice(
                message: _room.aiHostConfig.status == AIHostStatus.error
                    ? '模型回复超时或调用失败，行动已保留。房主可重试结算或更换 AI Host。'
                    : '主持连接已暂停，行动仍会保留。可等待重连或更换 AI Host。',
                action: PopupMenuButton<String>(
                  tooltip: '连接操作',
                  onSelected: (value) {
                    if (value == 'host') _pickHost();
                    if (value == 'retry') _retrySettlement();
                  },
                  itemBuilder: (_) => [
                    if (_isOwner)
                      const PopupMenuItem(
                        value: 'host',
                        child: Text('更换 Host'),
                      ),
                    if (_isOwner)
                      const PopupMenuItem(value: 'retry', child: Text('重试结算')),
                  ],
                ),
              ),
            Expanded(
              child: TrpgTimelineViewport(
                children: [
                  ...?session?.chatHistory
                      .where(
                        (message) =>
                            message.content.trim().isNotEmpty &&
                            !(message.messageType ==
                                    TRPGMessageType.gmMessage &&
                                AIGMOutputGuard.looksLikeInternalAnalysis(
                                  message.content,
                                )),
                      )
                      .map((message) => _messageCard(message)),
                  ...?session?.eventLog.reversed
                      .take(8)
                      .toList()
                      .reversed
                      .map(_eventCard),
                  ...?session?.ruleState.privateResolutions
                      .where((resolution) => resolution.visibleTo(_myId))
                      .toList()
                      .reversed
                      .take(3)
                      .toList()
                      .reversed
                      .map(_resolutionCard),
                  if (_notice != null) _noticeCard(),
                  if (processing)
                    TrpgInlineNotice(
                      message:
                          '正在等待模型回复／执行规则，已等待 ${_settlementWaitingSince == null ? 0 : DateTime.now().difference(_settlementWaitingSince!).inSeconds} 秒。单次请求最多 120 秒；云端整轮结算最多 5 分钟。',
                      action: _isOwner
                          ? TextButton(
                              onPressed:
                                  _settlementWaitingSince != null &&
                                      DateTime.now()
                                              .difference(
                                                _settlementWaitingSince!,
                                              )
                                              .inSeconds >=
                                          15
                                  ? _retrySettlement
                                  : null,
                              child: const Text('重试结算'),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            _mobileGameBar(
              session: session,
              character: myCharacter,
              isGroupTurn: isGroupTurn,
            ),
            if (_settlementSeconds case final seconds?)
              TrpgInlineNotice(message: '$seconds 秒后由主持人统一结算；点击右侧 × 可撤回并修改行动。'),
            TrpgComposer(
              onTools: _showMobileToolsSheet,
              guidePanel: session != null && _me.role != TRPGPlayerRole.humanGm
                  ? TrpgPlayerGuideCard(
                      session: session,
                      controller: _action,
                      playerId: _myId,
                      actionEnabled: !_chatMode,
                      inputEnabled:
                          composerEnabled &&
                          (!isGroupTurn || !_myTurnConfirmed),
                    )
                  : null,
              voiceButton: TrpgVoiceButton(
                controller: _action,
                settingsRepository: widget.settingsRepository,
                enabled:
                    composerEnabled &&
                    (!isGroupTurn || !_myTurnConfirmed || _chatMode),
              ),
              controller: _action,
              enabled: composerEnabled,
              sending: processing && !_chatMode,
              hintText: _chatMode
                  ? '发送玩家闲聊，不触发 GM…'
                  : humanGmCanResolve
                  ? '输入本回合主持叙事与结算结果…'
                  : _myTurnConfirmed && isGroupTurn
                  ? '行动已确认；仍可切换到“闲聊”发送消息…'
                  : _secretMode
                  ? '秘密行动，仅你与 GM 可见…'
                  : isGroupTurn
                  ? '描述行动后点击“确认本回合”；留空即跳过…'
                  : '描述你的行动、对话或意图…',
              onSend: _send,
              onCancelConfirmation:
                  !_chatMode &&
                      isGroupTurn &&
                      _myTurnConfirmed &&
                      turn?.phase == MultiplayerTurnPhase.collecting
                  ? _modifyTurnAction
                  : null,
              modeSelector: Wrap(
                spacing: 7,
                runSpacing: 5,
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.directions_run_outlined, size: 16),
                    selected: !_chatMode && !_secretMode,
                    onSelected: (_) => setState(() {
                      _chatMode = false;
                      _secretMode = false;
                    }),
                    label: const Text('行动'),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.forum_outlined, size: 16),
                    selected: _chatMode,
                    onSelected: (_) => setState(() {
                      _chatMode = true;
                      _secretMode = false;
                    }),
                    label: const Text('闲聊'),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.visibility_off_outlined, size: 16),
                    selected: _secretMode,
                    onSelected: (_) => setState(() {
                      _secretMode = true;
                      _chatMode = false;
                    }),
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

  Widget _mobileGameBar({
    required TRPGSession? session,
    required PlayerCharacter? character,
    required bool isGroupTurn,
  }) {
    final online = _room.players
        .where(
          (player) => player.connectionStatus == TRPGConnectionStatus.online,
        )
        .length;
    final location = session?.worldState.currentScene.title.isNotEmpty == true
        ? session!.worldState.currentScene.title
        : session?.worldState.location ?? '同步场景中';
    final turn = _turn;
    final countdown = _settlementSeconds;
    return Card(
      key: const ValueKey('mobile-game-control-bar'),
      margin: const EdgeInsets.fromLTRB(10, 3, 10, 4),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                key: const ValueKey('mobile-scene-button'),
                onTap: () => _showMobileSceneSheet(session, character),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Row(
                    children: [
                      const Icon(Icons.explore_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              '$online 人在线'
                              '${character == null ? '' : ' · HP ${character.hp}/${character.maxHp}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (isGroupTurn) ...[
              const VerticalDivider(width: 1, indent: 11, endIndent: 11),
              InkWell(
                key: const ValueKey('mobile-turn-button'),
                onTap: _showMobileTurnSheet,
                child: SizedBox(
                  width: 86,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.rule_folder_outlined, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '回合 ${turn?.roundNumber ?? ''}',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      Text(
                        countdown != null
                            ? '$countdown 秒后结算'
                            : turn?.phase == MultiplayerTurnPhase.collecting
                            ? '${turn?.confirmedPlayerIds.length ?? 0}/${turn?.expectedPlayerIds.length ?? 0} 已确认'
                            : '查看状态',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showMobileSceneSheet(
    TRPGSession? session,
    PlayerCharacter? character,
  ) async {
    if (session == null) return;
    final scene = session.worldState.currentScene;
    final stageShown = _showPresentationStage ?? false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TrpgSceneSummary(
                dense: true,
                title: scene.title.isEmpty
                    ? session.worldState.location
                    : scene.title,
                subtitle:
                    '${session.worldState.time} · ${session.worldState.weather}',
                facts: [
                  TrpgFact(
                    Icons.groups_outlined,
                    '${_room.players.where((player) => player.connectionStatus == TRPGConnectionStatus.online).length} 人在线',
                  ),
                  if (character != null)
                    TrpgFact(
                      Icons.favorite_outline,
                      'HP ${character.hp}/${character.maxHp}',
                    ),
                  if (session.ruleState.combatActive)
                    TrpgFact(
                      Icons.sports_martial_arts_outlined,
                      '战斗 · 第 ${session.ruleState.round} 回合',
                      emphasized: true,
                    ),
                ],
                trailing: IconButton.filledTonal(
                  tooltip: stageShown ? '收起演出画面' : '展开演出画面',
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    setState(() => _showPresentationStage = !stageShown);
                  },
                  icon: Icon(
                    stageShown
                        ? Icons.visibility_off_outlined
                        : Icons.image_outlined,
                  ),
                ),
              ),
              if (session.partyGroups.isNotEmpty)
                TrpgPartyDistribution(
                  groups: session.partyGroups,
                  names: {
                    for (final member in session.playerCharacters)
                      member.id: member.name,
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMobileTurnSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 18),
          child: _turn == null
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('当前没有需要统一确认的行动。'),
                )
              : _turnCollectionCard(),
        ),
      ),
    );
  }

  Future<void> _showMobileToolsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Text(
                  '资料与工具',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TrpgQuickActions(
                actions: _quickActionSpecs(
                  dismiss: () => Navigator.pop(sheetContext),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<TrpgActionSpec> _quickActionSpecs({VoidCallback? dismiss}) {
    VoidCallback launch(VoidCallback action) => () {
      dismiss?.call();
      if (dismiss == null) {
        action();
      } else {
        unawaited(Future<void>.delayed(Duration.zero, action));
      }
    };

    return [
      TrpgActionSpec(
        icon: Icons.search,
        label: '线索',
        onPressed: launch(() => _openPanel(TrpgPanelType.clues)),
      ),
      TrpgActionSpec(
        icon: Icons.map_outlined,
        label: '地图',
        onPressed: launch(() => _openPanel(TrpgPanelType.map)),
      ),
      TrpgActionSpec(
        icon: Icons.people_outline,
        label: '人物',
        onPressed: launch(() => _openPanel(TrpgPanelType.people)),
      ),
      TrpgActionSpec(
        icon: Icons.groups_outlined,
        label: '玩家',
        onPressed: launch(() => _showPlayers(context)),
      ),
      TrpgActionSpec(
        icon: Icons.lock_outline,
        label: '私密频道',
        onPressed: launch(() => unawaited(_showPrivateChannel())),
      ),
      TrpgActionSpec(
        icon: Icons.casino_outlined,
        label: '私骰',
        onPressed: launch(() => unawaited(_showPrivateDice())),
      ),
      TrpgActionSpec(
        icon: Icons.help_outline,
        label: '骰子说明',
        onPressed: launch(() => unawaited(showTrpgDiceHelp(context))),
      ),
    ];
  }

  Widget _messageCard(TRPGMessage message) {
    final player = _room.players
        .where((p) => p.playerId == message.playerId)
        .firstOrNull;
    final tone = switch (message.messageType) {
      TRPGMessageType.gmMessage => TrpgMessageTone.gm,
      TRPGMessageType.npcMessage => TrpgMessageTone.npc,
      TRPGMessageType.npcPlayerMessage => TrpgMessageTone.player,
      TRPGMessageType.playerMessage => TrpgMessageTone.player,
      TRPGMessageType.systemMessage => TrpgMessageTone.system,
      TRPGMessageType.diceMessage => TrpgMessageTone.dice,
    };
    return TrpgMessageBubble(
      label: message.messageType == TRPGMessageType.gmMessage
          ? 'AI GM'
          : message.messageType == TRPGMessageType.npcMessage
          ? 'NPC'
          : message.messageType == TRPGMessageType.npcPlayerMessage
          ? (player?.displayName ?? 'AI玩家')
          : player?.displayName ?? '玩家',
      content: message.content,
      tone: tone,
      time: message.createdAt,
    );
  }

  Widget _eventCard(TRPGEvent event) {
    if (!{
      TRPGEventType.diceRoll,
      TRPGEventType.skillCheck,
      TRPGEventType.hpChange,
      TRPGEventType.itemGain,
      TRPGEventType.itemLoss,
      TRPGEventType.questUpdate,
      TRPGEventType.sceneChange,
      TRPGEventType.damageApplied,
    }.contains(event.type))
      return const SizedBox.shrink();
    return TrpgEventTile(
      icon: _eventIcon(event.type),
      title: _eventLabel(event.type),
      details: _eventDetails(event),
    );
  }

  Widget _resolutionCard(PlayerResolution resolution) {
    final private = resolution.visibility == ResolutionVisibility.playerPrivate;
    return TrpgEventTile(
      icon: private ? Icons.lock_outline : Icons.groups_outlined,
      title: private ? '仅你可见 · ${resolution.title}' : resolution.title,
      details: resolution.entries.join('；'),
    );
  }

  IconData _eventIcon(TRPGEventType type) => switch (type) {
    TRPGEventType.hpChange ||
    TRPGEventType.damageApplied => Icons.favorite_outline,
    TRPGEventType.itemGain ||
    TRPGEventType.itemLoss => Icons.inventory_2_outlined,
    TRPGEventType.questUpdate => Icons.assignment_turned_in_outlined,
    TRPGEventType.sceneChange => Icons.place_outlined,
    TRPGEventType.skillCheck => Icons.fact_check_outlined,
    _ => Icons.casino_outlined,
  };

  String _eventLabel(TRPGEventType type) => switch (type) {
    TRPGEventType.diceRoll => '投骰结果',
    TRPGEventType.skillCheck => '技能检定',
    TRPGEventType.hpChange => '生命变化',
    TRPGEventType.damageApplied => '受到伤害',
    TRPGEventType.itemGain => '获得物品',
    TRPGEventType.itemLoss => '失去物品',
    TRPGEventType.questUpdate => '任务更新',
    TRPGEventType.sceneChange => '场景变化',
    _ => type.name,
  };

  String _eventDetails(TRPGEvent event) {
    final payload = event.payload;
    return switch (event.type) {
      TRPGEventType.diceRoll =>
        '${payload['diceType'] ?? 'D20'} · ${payload['total'] ?? payload['rolls'] ?? ''}',
      TRPGEventType.skillCheck => _skillCheckDetails(payload),
      TRPGEventType.hpChange =>
        '${payload['before'] ?? ''} → ${payload['after'] ?? ''} ${payload['reason'] ?? ''}',
      TRPGEventType.itemGain || TRPGEventType.itemLoss =>
        '${payload['itemId'] ?? (payload['item'] as Map?)?['name'] ?? ''}',
      TRPGEventType.questUpdate => '${payload['questId'] ?? ''}',
      TRPGEventType.sceneChange =>
        '${(payload['scene'] as Map?)?['title'] ?? ''}',
      _ => payload.values.where((value) => value != null).take(3).join(' · '),
    };
  }

  String _skillCheckDetails(Map<String, Object?> payload) {
    final explanation = payload['explanation']?.toString().trim();
    if (explanation != null && explanation.isNotEmpty) return explanation;
    final result = payload['result'];
    if (result is Map) {
      return ActionCheckResult.fromJson(
        result.cast<String, Object?>(),
      ).displayExplanation;
    }
    return '${payload['stat'] ?? payload['skill'] ?? '检定'} · '
        '${payload['total'] ?? payload['rolls'] ?? ''}';
  }

  void _showPlayers(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('玩家与角色状态')),
            ..._room.players.map((player) {
              final character = _session?.playerCharacters
                  .where((c) => c.playerId == player.playerId)
                  .firstOrNull;
              return ListTile(
                leading: CircleAvatar(
                  child: Text(player.displayName.characters.first),
                ),
                title: Text(player.displayName),
                subtitle: Text(
                  '${character?.name ?? '无角色'} · HP ${character?.hp ?? '-'}/${character?.maxHp ?? '-'}',
                ),
                trailing: Text(player.connectionStatus.name),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _noticeCard() => Card(
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text(_notice!),
      trailing: IconButton(
        onPressed: () => setState(() => _notice = null),
        icon: const Icon(Icons.close),
      ),
    ),
  );
}
