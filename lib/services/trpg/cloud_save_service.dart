import 'dart:convert';

import '../../models/trpg_models.dart';
import '../../repositories/trpg_session_repository.dart';
import 'account_client_service.dart';

class CloudSaveService {
  CloudSaveService({required this.account, required this.repository});
  final AccountClientService account;
  final TRPGSessionRepository repository;

  Future<List<Map<String, Object?>>> list() async {
    if (account.usesSupabase) {
      final response = await account.supabaseRest(
        'GET',
        '/campaigns?select=id,title,description,created_at,updated_at'
            '&order=updated_at.desc&limit=100',
      );
      return (response as List? ?? const [])
          .whereType<Map>()
          .map((row) => row.cast<String, Object?>())
          .toList();
    }
    final response = await account.get('/v1/campaigns');
    return (response['campaigns'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => row.cast<String, Object?>())
        .toList();
  }

  static Map<String, Object?> encode(TRPGSession session) {
    if (session.mode != TRPGMode.solo && session.metadata['localMultiplayerArchive'] != true) {
      throw StateError('多人房间需保存服务器权威快照，不能上传玩家视图作为完整存档');
    }
    final body = <String, Object?>{
      'title': session.title,
      'description': '${session.mode == TRPGMode.solo ? '单人跑团' : '多人个人记录'}备份 · ${DateTime.now().toLocal()}',
      'visibility': 'private',
      'state': {
        'format': session.mode == TRPGMode.solo ? 'ai-tavern-solo-save' : 'ai-tavern-personal-multiplayer-save',
        'version': 1,
        'session': session.toJson(),
      },
    };
    if (utf8.encode(jsonEncode(body)).length > 1900000) {
      throw StateError('该存档超过当前云备份的大小限制，请先使用本地导出保存');
    }
    return body;
  }

  static TRPGSession decode(Map<String, Object?> campaign) {
    final state = campaign['state'];
    if (state is! Map ||
        !const ['ai-tavern-solo-save', 'ai-tavern-personal-multiplayer-save'].contains(state['format']) ||
        state['version'] != 1 ||
        state['session'] is! Map) {
      throw StateError('这不是受支持的单人跑团备份');
    }
    final raw = (state['session'] as Map).cast<String, Object?>();
    // Do not silently migrate future or legacy schemas and lose unknown fields.
    if (raw['schemaVersion'] != trpgSchemaVersion ||
        (raw['mode'] != 'solo' && !(raw['mode'] == 'multiplayer' && state['format'] == 'ai-tavern-personal-multiplayer-save' && (raw['metadata'] as Map?)?['localMultiplayerArchive'] == true)) ||
        raw['id'] is! String ||
        (raw['id'] as String).isEmpty) {
      throw StateError('存档版本或模式不兼容，请使用相同版本的客户端恢复');
    }
    return TRPGSession.fromJson(raw);
  }

  Future<void> upload(TRPGSession session) async {
    final body = encode(session);
    if (account.usesSupabase) {
      final userId = account.tokens?.account.userId;
      if (userId == null || userId.isEmpty) throw StateError('需要登录账号');
      await account.supabaseRest(
        'POST',
        '/campaigns?select=id,title,description,created_at,updated_at',
        body: {...body, 'owner_id': userId},
        prefer: 'return=representation',
      );
      return;
    }
    await account.post('/v1/campaigns', body);
  }

  Future<String> restore(String cloudId) async {
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(cloudId)) {
      throw StateError('存档编号无效');
    }
    Object? campaign;
    if (account.usesSupabase) {
      final response = await account.supabaseRest(
        'GET',
        '/campaigns?id=eq.$cloudId&select=*&limit=1',
      );
      campaign = response is List && response.isNotEmpty
          ? response.first
          : null;
    } else {
      final response = await account.get('/v1/campaigns/$cloudId');
      campaign = response['campaign'];
    }
    if (campaign is! Map) throw StateError('服务器没有返回存档');
    final session = decode(campaign.cast<String, Object?>());
    await repository.upsert(session, onlyIfAbsent: true);
    return session.title;
  }
}
