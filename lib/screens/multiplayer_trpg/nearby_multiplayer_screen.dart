import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/campaign_models.dart';
import '../../models/multiplayer_models.dart';
import '../../models/nearby_models.dart';
import '../../models/social_models.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/trpg_session_repository.dart';
import '../../services/ai_service.dart';
import '../../services/trpg/android_nearby_transport.dart';
import '../../services/trpg/multiplayer_transport.dart';
import '../../services/trpg/nearby_connections_manager.dart';
import '../../services/trpg/nearby_host_bridge.dart';
import 'multiplayer_lobby_screen.dart';

class NearbyMultiplayerScreen extends StatefulWidget {
  const NearbyMultiplayerScreen({
    required this.campaigns,
    required this.selectedCampaign,
    required this.playerName,
    required this.roomName,
    required this.allowPrivateChat,
    required this.account,
    required this.apiRepository,
    required this.aiService,
    required this.repository,
    required this.settingsRepository,
    super.key,
  });

  final List<CampaignDocument> campaigns;
  final CampaignDocument? selectedCampaign;
  final String playerName, roomName;
  final bool allowPrivateChat;
  final AuthTokens? account;
  final ApiRepository apiRepository;
  final AiService aiService;
  final TRPGSessionRepository repository;
  final SettingsRepository settingsRepository;

  @override
  State<NearbyMultiplayerScreen> createState() =>
      _NearbyMultiplayerScreenState();
}

class _NearbyMultiplayerScreenState extends State<NearbyMultiplayerScreen> {
  ProximityConnectionsManager _manager = NearbyConnectionsManager.instance;
  late final _playerName = TextEditingController(text: widget.playerName);
  late final _roomName = TextEditingController(text: widget.roomName);
  late CampaignDocument? _campaign = widget.selectedCampaign;
  final _rooms = <String, NearbyRoomAdvertisement>{};
  StreamSubscription<NearbyPlatformEvent>? _eventSub;
  NearbySupportState? _support;
  NearbyPermissionState? _permissions;
  bool _busy = false;
  bool _discovering = false;
  String? _error;
  MultiplayerCredentials? _savedCredentials;

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  Future<void> _refreshState() async {
    final googleManager = NearbyConnectionsManager.instance;
    final googleSupport = await googleManager.supportState();
    final directManager = WifiDirectConnectionsManager.instance;
    final directSupport = googleSupport.available
        ? null
        : await directManager.supportState();
    final selectedManager = googleSupport.available
        ? googleManager
        : directManager;
    final support = googleSupport.available
        ? googleSupport
        : (directSupport ?? googleSupport);
    final permissions = support.available
        ? await selectedManager.permissionState()
        : const NearbyPermissionState(granted: false);
    MultiplayerCredentials? saved;
    final raw = await widget.apiRepository.readMultiplayerCredentials();
    if (raw.isNotEmpty) {
      try {
        saved = MultiplayerCredentials.fromJson(
          (jsonDecode(raw) as Map).cast<String, Object?>(),
        );
      } catch (_) {}
    }
    if (!mounted) return;
    await _eventSub?.cancel();
    _manager = selectedManager;
    _eventSub = _manager.events.listen(_onEvent);
    setState(() {
      _support = support;
      _permissions = permissions;
      _savedCredentials = saved;
    });
  }

  void _onEvent(NearbyPlatformEvent event) {
    if (!mounted) return;
    if (event.type == 'endpointFound') {
      final endpointId = event.data['endpointId']?.toString() ?? '';
      final room = NearbyRoomAdvertisement.tryParse(
        endpointId,
        event.data['endpointName']?.toString() ?? '',
      );
      if (room != null) setState(() => _rooms[endpointId] = room);
    } else if (event.type == 'endpointLost') {
      setState(() => _rooms.remove(event.data['endpointId']?.toString()));
    } else if (event.type == 'error') {
      setState(() => _error = event.data['message']?.toString() ?? '附近联机错误');
    }
  }

  Future<bool> _ensurePermissions() async {
    final support = _support ?? await _manager.supportState();
    if (!support.available) {
      setState(() => _error = '此设备既没有可用的 Google Nearby，也不支持系统 Wi-Fi Direct。');
      return false;
    }
    var permissions = await _manager.permissionState();
    if (!permissions.granted) {
      permissions = await _manager.requestPermissions();
      if (mounted) setState(() => _permissions = permissions);
    }
    if (!permissions.granted) {
      setState(() => _error = '没有附近设备权限。你可以在系统设置中重新授权。');
      return false;
    }
    return true;
  }

  Future<void> _createRoom() async {
    if (!await _ensurePermissions()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final bridge = NearbyHostBridge(manager: _manager);
    final client = MultiplayerClient();
    try {
      await bridge.startAuthority();
      await client.createRoom(
        endpoint: bridge.localEndpoint,
        roomName: _roomName.text.trim().isEmpty
            ? '附近跑团'
            : _roomName.text.trim(),
        playerName: _playerName.text.trim().isEmpty
            ? '房主'
            : _playerName.text.trim(),
        maxPlayers: 5,
        campaignId: _campaign?.id ?? 'mist_harbor_test',
        campaignSnapshot: _campaign?.toJson(),
        allowPlayerPrivateChat: widget.allowPrivateChat,
        account: widget.account,
      );
      final snapshot = await client.states.first.timeout(
        const Duration(seconds: 20),
      );
      final owner = snapshot.room.players.firstWhere(
        (player) => player.playerId == snapshot.room.ownerPlayerId,
      );
      await bridge.advertise(
        NearbyRoomAdvertisement(
          endpointId: '',
          roomId: snapshot.room.roomId,
          roomCode: snapshot.room.roomCode,
          roomName: snapshot.room.roomName,
          ownerName: owner.displayName,
          currentPlayers: snapshot.room.players.length,
          maxPlayers: snapshot.room.maxPlayers,
        ),
      );
      await _saveCredentials(client);
      if (!mounted) return;
      await Navigator.pushReplacement<void, void>(
        context,
        MaterialPageRoute(
          builder: (_) => MultiplayerLobbyScreen(
            settingsRepository: widget.settingsRepository,
            repository: widget.repository,
            initialSnapshot: snapshot,
            client: client,
            apiRepository: widget.apiRepository,
            aiService: widget.aiService,
            nearbyHostBridge: bridge,
          ),
        ),
      );
    } catch (error) {
      await client.close();
      await bridge.close();
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleDiscovery() async {
    if (_discovering) {
      await _manager.stopDiscovery();
      if (mounted) setState(() => _discovering = false);
      return;
    }
    if (!await _ensurePermissions()) return;
    setState(() {
      _rooms.clear();
      _discovering = true;
      _error = null;
    });
    try {
      await _manager.startDiscovery();
    } catch (error) {
      if (mounted) {
        setState(() {
          _discovering = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _joinRoom(NearbyRoomAdvertisement room) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final verificationFuture = _manager.events
          .where(
            (event) =>
                event.type == 'verificationRequired' &&
                event.data['endpointId'] == room.endpointId,
          )
          .map(NearbyVerificationRequest.fromEvent)
          .first
          .timeout(const Duration(seconds: 30));
      await _manager.requestConnection(
        room.endpointId,
        _playerName.text.trim().isEmpty ? '玩家' : _playerName.text.trim(),
      );
      final request = await verificationFuture;
      if (!mounted) return;
      final accepted = await _showVerification(request);
      if (accepted != true) {
        await _manager.rejectConnection(room.endpointId);
        return;
      }
      final connectedFuture = _manager.events
          .where(
            (event) =>
                event.type == 'connected' &&
                event.data['endpointId'] == room.endpointId,
          )
          .first
          .timeout(const Duration(seconds: 35));
      await _manager.acceptConnection(room.endpointId);
      await connectedFuture;
      await _manager.stopDiscovery();
      _discovering = false;
      final transport = AndroidNearbyTransport(manager: _manager);
      final client = MultiplayerClient(transport: transport);
      final endpoint = AndroidNearbyTransport.endpointFor(room.endpointId);
      final saved = _savedCredentials;
      if (saved != null && saved.roomId == room.roomId) {
        await client.reconnect(
          MultiplayerCredentials(
            endpoint: endpoint,
            roomId: saved.roomId,
            playerId: saved.playerId,
            sessionToken: saved.sessionToken,
            lastRevision: saved.lastRevision,
          ),
        );
      } else {
        await client.joinRoom(
          endpoint: endpoint,
          roomCode: room.roomCode,
          playerName: _playerName.text.trim().isEmpty
              ? '玩家'
              : _playerName.text.trim(),
          account: widget.account,
        );
      }
      final snapshot = await client.states.first.timeout(
        const Duration(seconds: 30),
      );
      await _saveCredentials(client);
      if (!mounted) return;
      await Navigator.pushReplacement<void, void>(
        context,
        MaterialPageRoute(
          builder: (_) => MultiplayerLobbyScreen(
            settingsRepository: widget.settingsRepository,
            initialSnapshot: snapshot,
            repository: widget.repository,
            client: client,
            apiRepository: widget.apiRepository,
            aiService: widget.aiService,
          ),
        ),
      );
    } catch (error) {
      await _manager.disconnectEndpoint(room.endpointId);
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _showVerification(NearbyVerificationRequest request) =>
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('核对连接数字'),
          content: Text(
            '请与房主当面核对两台设备：\n\n${request.authenticationDigits}\n\n'
            '只有数字完全一致才确认连接。',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('数字一致'),
            ),
          ],
        ),
      );

  Future<void> _saveCredentials(MultiplayerClient client) async {
    final credentials = client.credentials;
    if (credentials != null) {
      await widget.apiRepository.writeMultiplayerCredentials(
        jsonEncode(credentials.toJson()),
      );
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    if (_discovering) unawaited(_manager.stopDiscovery());
    _playerName.dispose();
    _roomName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final support = _support;
    final permissions = _permissions;
    return Scaffold(
      appBar: AppBar(title: const Text('附近联机')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const ListTile(
              leading: Icon(Icons.bluetooth_searching),
              title: Text('手机直接发现附近房间'),
              subtitle: Text(
                '无需同一 Wi-Fi、路由器、公共 IP 或电脑服务器。房主手机保存权威状态；AI 主持仍可由任意玩家提供。',
              ),
            ),
          ),
          if (support?.available == true)
            Card(
              child: ListTile(
                leading: Icon(
                  support!.backend == 'wifiDirect'
                      ? Icons.wifi_find
                      : Icons.g_mobiledata,
                ),
                title: Text(
                  support.backend == 'wifiDirect'
                      ? '无 Google 框架模式：Wi-Fi Direct'
                      : 'Google Nearby 模式',
                ),
                subtitle: Text(
                  support.backend == 'wifiDirect'
                      ? '使用 Android 系统点对点连接，不需要 Google Play、互联网或路由器。'
                      : '使用 Google Play services Nearby Connections。',
                ),
              ),
            ),
          if (support != null && !support.available)
            _errorCard('Google Nearby 与系统 Wi-Fi Direct 都不可用。你仍可使用互联网联机。'),
          if (permissions != null && !permissions.granted)
            Card(
              child: ListTile(
                leading: const Icon(Icons.phonelink_lock),
                title: const Text('需要附近设备权限'),
                subtitle: const Text('权限只用于发现和连接附近手机；拒绝后不会自动反复弹窗。'),
                trailing: Wrap(
                  children: [
                    TextButton(
                      onPressed: _busy ? null : _ensurePermissions,
                      child: const Text('授权'),
                    ),
                    if (permissions.mayNeedSettings)
                      TextButton(
                        onPressed: _manager.openSettings,
                        child: const Text('系统设置'),
                      ),
                  ],
                ),
              ),
            ),
          TextField(
            controller: _playerName,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: '玩家昵称',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
          Text('创建附近房间', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _roomName,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: '房间名称'),
                  ),
                  if (widget.campaigns.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<CampaignDocument>(
                      initialValue: _campaign,
                      decoration: const InputDecoration(labelText: '选择剧本'),
                      items: widget.campaigns
                          .map(
                            (campaign) => DropdownMenuItem(
                              value: campaign,
                              child: Text(campaign.title),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _campaign = value),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy || support?.available != true
                          ? null
                          : _createRoom,
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('创建并广播房间（最多 5 人）'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '附近房间',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy || support?.available != true
                    ? null
                    : _toggleDiscovery,
                icon: Icon(_discovering ? Icons.stop : Icons.search),
                label: Text(_discovering ? '停止搜索' : '搜索房间'),
              ),
            ],
          ),
          if (_discovering && _rooms.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('正在搜索附近房间……')),
            ),
          for (final room in _rooms.values)
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.groups)),
                title: Text(room.roomName),
                subtitle: Text(
                  '房主：${room.ownerName} · ${room.currentPlayers}/${room.maxPlayers} 人'
                  '${room.passwordRequired ? ' · 需要密码' : ''}'
                  '${_savedCredentials?.roomId == room.roomId ? ' · 可恢复上次身份' : ''}',
                ),
                trailing: FilledButton(
                  onPressed: _busy ? null : () => _joinRoom(room),
                  child: const Text('加入'),
                ),
              ),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null) _errorCard(_error!),
        ],
      ),
    );
  }

  Widget _errorCard(String message) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      leading: const Icon(Icons.error_outline),
      title: const Text('附近联机提示'),
      subtitle: Text(message),
    ),
  );
}
