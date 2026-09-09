import '../../app/skins/skin_icon.dart';
import '../../app/skins/character_theme.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/multiplayer_models.dart';
import '../../models/campaign_models.dart';
import '../../models/trpg_models.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/campaign_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/trpg_session_repository.dart';
import '../../services/ai_service.dart';
import '../../services/trpg/multiplayer_transport.dart';
import '../../services/trpg/account_client_service.dart';
import '../../services/trpg/server_environment.dart';
import '../../models/social_models.dart';
import 'multiplayer_lobby_screen.dart';
import 'account_screen.dart';
import 'social_campaign_screen.dart';
import 'cloud_saves_screen.dart';
import 'local_archives_screen.dart';
import '../solo_trpg/solo_session_screen.dart';
import '../../services/trpg/cloud_save_service.dart';
import 'nearby_multiplayer_screen.dart';
import '../campaigns/campaign_library_screen.dart';
import '../rule_library/rule_library_screen.dart';
import '../../services/trpg/campaign_template_service.dart';

class MultiplayerHomeScreen extends StatefulWidget {
  const MultiplayerHomeScreen({
    required this.repository,
    required this.campaignRepository,
    required this.characterRepository,
    required this.apiRepository,
    required this.settingsRepository,
    required this.aiService,
    required this.onExitToModes,
    super.key,
  });
  final TRPGSessionRepository repository;
  final CampaignRepository campaignRepository;
  final CharacterCardRepository characterRepository;
  final ApiRepository apiRepository;
  final SettingsRepository settingsRepository;
  final AiService aiService;
  final VoidCallback onExitToModes;

  @override
  State<MultiplayerHomeScreen> createState() => _MultiplayerHomeScreenState();
}

class _MultiplayerHomeScreenState extends State<MultiplayerHomeScreen> {
  final _endpoint = TextEditingController(
    text: ServerEnvironment.hasProductionServer
        ? ServerEnvironment.gameServerUrl
        : 'ws://127.0.0.1:8765/ws',
  );
  final _playerName = TextEditingController(text: '玩家');
  final _roomName = TextEditingController(text: '雾港联机团');
  final _roomCode = TextEditingController();
  MultiplayerCredentials? _saved;
  bool _busy = false;
  String? _error;
  List<CampaignDocument> _campaigns = const [];
  CampaignDocument? _selectedCampaign;
  bool _allowPrivateChat = true;
  late final AccountClientService _accountService = AccountClientService(
    apiRepository: widget.apiRepository,
  );
  AuthTokens? _account;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    var campaigns = await widget.campaignRepository.getAll();
    final holyGrail = const CampaignTemplateService().holyGrailWar();
    final installed = campaigns
        .where((value) => value.id == holyGrail.id)
        .firstOrNull;
    final installedVersion =
        (installed?.metadata['holyGrailTemplateVersion'] as num?)?.toInt() ?? 0;
    if (installed == null ||
        (installed.source == CampaignSourceType.template &&
            installedVersion < 2)) {
      await widget.campaignRepository.upsert(holyGrail);
      campaigns = await widget.campaignRepository.getAll();
    }
    final raw = await widget.apiRepository.readMultiplayerCredentials();
    _accountService.baseUrl = _httpEndpoint(_endpoint.text);
    final account = await _accountService.restore();
    if (mounted) {
      setState(() {
        _campaigns = campaigns;
        _selectedCampaign = campaigns.firstOrNull;
        _account = account;
      });
    }
    if (raw.isEmpty || !mounted) return;
    try {
      final saved = MultiplayerCredentials.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
      setState(() {
        _saved = saved;
        final savedUri = Uri.tryParse(saved.endpoint.trim());
        final savedHost = savedUri?.host.toLowerCase();
        final savedIsLocal =
            savedHost == '127.0.0.1' ||
            savedHost == 'localhost' ||
            savedHost == '::1';
        final savedIsOldWorker = savedHost?.endsWith('.workers.dev') ?? false;
        if (ServerEnvironment.hasProductionServer && savedIsLocal) {
          _saved = null;
          _endpoint.text = ServerEnvironment.gameServerUrl;
        } else if (ServerEnvironment.hasProductionServer &&
            savedUri != null &&
            savedUri.path.contains('/v1/rooms/') &&
            (savedIsOldWorker ||
                savedHost ==
                    Uri.parse(
                      ServerEnvironment.gameServerUrl,
                    ).host.toLowerCase())) {
          // Old public builds stored the direct workers.dev socket URL. That
          // host is unreachable on some mobile networks. Keep the room token,
          // but move its socket path and query onto the configured relay.
          final production = Uri.parse(ServerEnvironment.gameServerUrl);
          final roomPath = savedUri.path.substring(
            savedUri.path.indexOf('/v1/rooms/'),
          );
          final relaySocket = production.replace(
            scheme: 'wss',
            path:
                '${production.path.replaceFirst(RegExp(r'/+$'), '')}$roomPath',
            query: savedUri.query.isEmpty ? null : savedUri.query,
            fragment: null,
          );
          _saved = MultiplayerCredentials(
            endpoint: relaySocket.toString(),
            roomId: saved.roomId,
            playerId: saved.playerId,
            sessionToken: saved.sessionToken,
            playerSessionId: saved.playerSessionId,
            lastRevision: saved.lastRevision,
          );
          _endpoint.text = ServerEnvironment.gameServerUrl;
        } else {
          _endpoint.text = saved.endpoint;
        }
      });
    } catch (_) {}
  }

  Future<void> _run(
    Future<void> Function(MultiplayerClient client) action,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = MultiplayerClient(
      transport: WebSocketTransport(authorizationToken: _account?.accessToken),
    );
    try {
      if (_account != null &&
          _account!.expiresAt.isBefore(
            DateTime.now().add(const Duration(minutes: 1)),
          )) {
        _account = await _accountService.refresh();
        (client.transport as WebSocketTransport).authorizationToken =
            _account!.accessToken;
      }
      await action(client);
      final snapshot =
          client.snapshot ??
          await client.states.first.timeout(const Duration(seconds: 15));
      final credentials = client.credentials;
      if (credentials == null) throw StateError('服务器没有返回玩家凭证');
      await widget.apiRepository.writeMultiplayerCredentials(
        jsonEncode(credentials.toJson()),
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => MultiplayerLobbyScreen(
            repository: widget.repository,
            initialSnapshot: snapshot,
            client: client,
            apiRepository: widget.apiRepository,
            aiService: widget.aiService,
          ),
        ),
      );
    } catch (error) {
      await client.close();
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (!_validateInternetEndpoint()) return;
    await _run(
      (client) => client.createRoom(
        endpoint: _endpoint.text.trim(),
        roomName: _roomName.text.trim(),
        playerName: _playerName.text.trim(),
        maxPlayers: 4,
        campaignId: _selectedCampaign?.id ?? 'mist_harbor_test',
        campaignSnapshot: _selectedCampaign?.toJson(),
        allowPlayerPrivateChat: _allowPrivateChat,
        account: _account,
      ),
    );
  }

  Future<void> _join() async {
    if (!_validateInternetEndpoint()) return;
    await _run(
      (client) => client.joinRoom(
        endpoint: _endpoint.text.trim(),
        roomCode: _roomCode.text,
        playerName: _playerName.text.trim(),
        account: _account,
      ),
    );
  }

  bool _validateInternetEndpoint() {
    if (!Platform.isAndroid) return true;
    final uri = Uri.tryParse(_endpoint.text.trim());
    final host = uri?.host.toLowerCase();
    if (host != '127.0.0.1' && host != 'localhost' && host != '::1') {
      return true;
    }
    setState(() {
      _error =
          '手机上的 127.0.0.1 只代表这台手机自己，这里没有互联网联机服务器。'
          '如果要加入附近房间，请点击上方“附近联机”，然后选择“搜索房间”，不要在这里输入附近房间码。';
    });
    return false;
  }

  Future<void> _reconnect() async {
    final saved = _saved;
    if (saved == null) return;
    await _run((client) => client.reconnect(saved));
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _playerName.dispose();
    _roomName.dispose();
    _roomCode.dispose();
    _accountService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onExitToModes,
          icon: const SkinIcon(Icons.home_outlined),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('多人跑团'),
            Text('公网 / 局域网 · 服务端权威', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(tooltip: '本地存档', icon: const Icon(Icons.save_outlined), onPressed: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => LocalArchivesScreen(
            repository: widget.repository,
            onBackup: (session) async {
              await _accountService.restore();
              if (_accountService.tokens == null) throw StateError('请先在多人首页登录，再备份云端');
              await CloudSaveService(account: _accountService, repository: widget.repository).upload(session);
            },
            onPlay: (session) async {
              await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => SoloSessionScreen(session: session, repository: widget.repository, apiRepository: widget.apiRepository, settingsRepository: widget.settingsRepository, aiService: widget.aiService)));
            },
          )))),
          IconButton(
            tooltip: '规则资料库',
            icon: const SkinIcon(Icons.menu_book_outlined),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const RuleLibraryScreen()),
            ),
          ),
          IconButton(
            tooltip: _account == null ? '登录账号' : '@${_account!.account.handle}',
            icon: SkinIcon(
              _account == null
                  ? Icons.account_circle_outlined
                  : Icons.account_circle,
            ),
            onPressed: _openAccount,
          ),
          IconButton(
            tooltip: '剧本库',
            icon: const SkinIcon(Icons.auto_stories_outlined),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => CampaignLibraryScreen(
                  repository: widget.campaignRepository,
                  characterRepository: widget.characterRepository,
                  apiRepository: widget.apiRepository,
                  aiService: widget.aiService,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color:
                    _selectedCampaign?.campaignType == CampaignType.holyGrailWar
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: ListTile(
                  leading: const SkinIcon(Icons.auto_awesome),
                  title: const Text('圣杯战争多人御主模式'),
                  subtitle: const Text('选择“冬木残响”模板；服务器会隔离每名御主的真名、位置、计划和私有情报。'),
                  trailing: FilledButton(
                    onPressed: () {
                      final campaign = _campaigns
                          .where(
                            (value) =>
                                value.campaignType == CampaignType.holyGrailWar,
                          )
                          .firstOrNull;
                      if (campaign != null) {
                        setState(() => _selectedCampaign = campaign);
                      }
                    },
                    child: Text(
                      _selectedCampaign?.campaignType ==
                              CampaignType.holyGrailWar
                          ? '已选择'
                          : '选择',
                    ),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: SkinIcon(
                    _account == null
                        ? Icons.person_off_outlined
                        : Icons.cloud_done_outlined,
                  ),
                  title: Text(
                    _account == null
                        ? '游客模式'
                        : '${_account!.account.displayName} · @${_account!.account.handle}',
                  ),
                  subtitle: Text(
                    _account == null
                        ? '可使用临时局域网房间；好友、永久战役和跨设备继续需要登录。'
                        : '账号已登录。API Key 仍只保存在本设备。',
                  ),
                  trailing: _account == null
                      ? TextButton(
                          onPressed: _openAccount,
                          child: const Text('登录'),
                        )
                      : TextButton(
                          onPressed: _openCampaigns,
                          child: const Text('我的战役'),
                        ),
                ),
              ),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: const SkinIcon(Icons.wifi_tethering),
                  title: const Text('附近联机'),
                  subtitle: Text(
                    Platform.isAndroid
                        ? '不需要同一 Wi-Fi、路由器、服务器或手动输入 IP。支持 2～5 人。'
                        : '仅 Android 手机支持；桌面端不会伪装成附近设备。',
                  ),
                  trailing: FilledButton(
                    onPressed: _busy || !Platform.isAndroid
                        ? null
                        : _openNearby,
                    child: const Text('进入'),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 14, 4, 8),
                child: Row(
                  children: [
                    SkinIcon(Icons.public, size: 20),
                    SizedBox(width: 8),
                    Text('互联网 / 局域网联机'),
                  ],
                ),
              ),
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: const ListTile(
                  leading: SkinIcon(Icons.info_outline),
                  title: Text('附近房间不要在这里输入房间码'),
                  subtitle: Text(
                    '此区域只连接已经启动的互联网/局域网服务器。手机加入附近房间请返回上方“附近联机”并搜索。127.0.0.1 仅适用于服务器运行在本机的情况。',
                  ),
                ),
              ),
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  leading: SkinIcon(Icons.dns_outlined),
                  title: Text(
                    ServerEnvironment.hasProductionServer
                        ? '已配置公网服务器'
                        : '公网尚未配置，可先使用局域网',
                  ),
                  subtitle: Text(
                    ServerEnvironment.hasProductionServer
                        ? '公网使用 HTTPS / WSS 和账号登录；API Key 只保存在主持设备。'
                        : '局域网需先在 PC 启动服务器，手机填写 PC 的局域网 IP。公网地址需部署后配置，当前没有默认线上服务。',
                  ),
                ),
              ),
              TextField(
                controller: _endpoint,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'ws://192.168.1.10:8765/ws',
                  prefixIcon: SkinIcon(Icons.lan),
                ),
              ),
              TextField(
                controller: _playerName,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '玩家昵称',
                  prefixIcon: SkinIcon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _roomName,
                        enabled: !_busy,
                        decoration: const InputDecoration(labelText: '新房间名称'),
                      ),
                      if (_campaigns.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<CampaignDocument>(
                          initialValue: _selectedCampaign,
                          decoration: const InputDecoration(labelText: '选择剧本'),
                          items: _campaigns
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value.title),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) =>
                                    setState(() => _selectedCampaign = value),
                        ),
                        SwitchListTile(
                          value: _allowPrivateChat,
                          onChanged: _busy
                              ? null
                              : (value) =>
                                    setState(() => _allowPrivateChat = value),
                          title: const Text('允许玩家私聊'),
                          subtitle: const Text('GM 私聊与秘密行动不受此开关影响'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _create,
                          icon: const SkinIcon(Icons.add),
                          label: const Text('创建真实联机房间'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _roomCode,
                        enabled: !_busy,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: '六位房间码',
                          prefixIcon: SkinIcon(Icons.password),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _join,
                          icon: const SkinIcon(Icons.login),
                          label: const Text('通过房间码加入'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_saved != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _reconnect,
                  icon: const SkinIcon(Icons.restore),
                  label: const Text('恢复上次多人房间'),
                ),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: ThemedLoadingIndicator()),
                ),
              if (_error != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const SkinIcon(Icons.error_outline),
                    title: const Text('连接失败'),
                    subtitle: Text(_error!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAccount() async {
    _accountService.baseUrl = _httpEndpoint(_endpoint.text);
    if (_account != null) {
      await _showAccountMenu();
      return;
    }
    final value = await Navigator.push<AuthTokens>(
      context,
      MaterialPageRoute(
        builder: (_) => AccountScreen(service: _accountService),
      ),
    );
    if (value != null && mounted) setState(() => _account = value);
  }

  Future<void> _openNearby() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => NearbyMultiplayerScreen(
          repository: widget.repository,
          campaigns: _campaigns,
          selectedCampaign: _selectedCampaign,
          playerName: _playerName.text.trim(),
          roomName: _roomName.text.trim(),
          allowPrivateChat: _allowPrivateChat,
          account: _account,
          apiRepository: widget.apiRepository,
          aiService: widget.aiService,
        ),
      ),
    );
  }

  Future<void> _showAccountMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const SkinIcon(Icons.account_circle),
              title: Text(_account!.account.displayName),
              subtitle: Text('@${_account!.account.handle}'),
            ),
            ListTile(
              leading: const SkinIcon(Icons.auto_stories_outlined),
              title: const Text('我的战役'),
              onTap: () => Navigator.pop(context, 'campaigns'),
            ),
            if (!_accountService.usesSupabase)
              ListTile(
                leading: const SkinIcon(Icons.devices_outlined),
                title: const Text('登录设备'),
                onTap: () => Navigator.pop(context, 'devices'),
              ),
            ListTile(
              leading: const SkinIcon(Icons.logout),
              title: const Text('退出登录'),
              subtitle: const Text('不会删除本地酒馆或单人存档'),
              onTap: () => Navigator.pop(context, 'logout'),
            ),
          ],
        ),
      ),
    );
    if (action == 'campaigns') await _openCampaigns();
    if (action == 'devices') await _showDevices();
    if (action == 'logout') {
      await _accountService.logout();
      if (mounted) setState(() => _account = null);
    }
  }

  Future<void> _showDevices() async {
    try {
      final response = await _accountService.get('/api/devices');
      final devices = (response['devices'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => value.cast<String, Object?>())
          .toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('登录设备'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: devices
                  .map(
                    (value) => ListTile(
                      leading: SkinIcon(
                        value['platform'] == 'android'
                            ? Icons.phone_android
                            : Icons.computer,
                      ),
                      title: Text(value['deviceName']?.toString() ?? '未知设备'),
                      subtitle: Text(
                        '${value['platform']} · Host ${value['supportsAIHost'] == true ? '可用' : '不可用'}',
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _openCampaigns() async {
    final account = _account?.account;
    if (account == null) return;
    _accountService.baseUrl = _httpEndpoint(_endpoint.text);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _accountService.usesSupabase
            ? CloudSavesScreen(
                service: CloudSaveService(
                  account: _accountService,
                  repository: widget.repository,
                ),
              )
            : SocialCampaignScreen(
                service: _accountService,
                account: account,
                onContinue: _continueCampaign,
              ),
      ),
    );
  }

  Future<void> _continueCampaign(PersistentCampaignRoom room) async {
    if (mounted) Navigator.pop(context);
    final local = _campaigns
        .where((value) => value.id == room.campaignId)
        .firstOrNull;
    await _run(
      (client) => client.createRoom(
        endpoint: _endpoint.text.trim(),
        roomName: room.title,
        playerName: _account?.account.displayName ?? _playerName.text.trim(),
        campaignId: room.campaignId,
        campaignSnapshot: local?.toJson(),
        maxPlayers: room.maxMembers.clamp(2, 6),
        allowPlayerPrivateChat: _allowPrivateChat,
        account: _account,
        kind: CampaignRoomKind.persistent,
        persistentCampaignRoomId: room.id,
      ),
    );
  }

  String _httpEndpoint(String endpoint) {
    final uri = Uri.parse(endpoint.trim());
    return uri
        .replace(
          scheme: uri.scheme == 'wss' ? 'https' : 'http',
          query: null,
          fragment: null,
        )
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }
}
