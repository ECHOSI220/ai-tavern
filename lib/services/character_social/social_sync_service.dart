import '../../repositories/character_social_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../models/character.dart';
import 'social_avatar_codec.dart';
import '../trpg/account_client_service.dart';

class SocialSyncService {
  SocialSyncService(this.repository, this.account);
  final CharacterSocialRepository repository;
  final AccountClientService account;
  bool _busy = false;
  Future<int> sync() async {
    if (_busy) return 0;
    if (repository.owner == 'local' ||
        account.tokens?.account.userId != repository.owner) {
      throw StateError('请登录同一账号后同步；本机游客数据不会自动上传');
    }
    _busy = true;
    var changed = 0;
    try {
      for (var batch = 0; batch < 100; batch++) {
        final pending = await repository.pending();
        if (pending.isEmpty) break;
        final result = await account.supabaseRest(
          'POST',
          '/rpc/social_apply_batch',
          body: {'changes': pending.map((r) => r.toCloud()).toList()},
        );
        if (result is! List) throw StateError('同步响应格式错误');
        for (final item in result.whereType<Map>()) {
          final remote = (item['record'] as Map).cast<String, Object?>();
          final sent = pending.where((r) => r.id == remote['id']).firstOrNull;
          await repository.acceptRemote(
            remote,
            sent: item['accepted'] == true ? sent : null,
          );
          changed++;
        }
      }
      // Full keyset scan deliberately avoids missing late commits with sequence cursors.
      // Each page is bounded; local edits remain queued while conflicts are explicit.
      String? after;
      while (true) {
        final result = await account.supabaseRest(
          'GET',
          '/character_social_records?select=*&order=id.asc&limit=200'
              '${after == null ? '' : '&id=gt.${Uri.encodeComponent(after)}'}',
        );
        if (result is! List) throw StateError('云端数据格式错误');
        for (final row in result.whereType<Map>()) {
          final before = await repository.get(row['id'] as String);
          await repository.acceptRemote(row.cast<String, Object?>());
          if (row['kind'] == 'card' &&
              row['deleted'] != true &&
              (before == null ||
                  (row['version'] as int) > before.baseVersion)) {
            final accepted = await repository.get(row['id'] as String);
            if (accepted != null &&
                !accepted.dirty &&
                accepted.conflict == null) {
              final card = await SocialAvatarCodec.materialize(
                Character.fromJson(accepted.data),
              );
              await CharacterCardRepository(
                repository.storage,
              ).upsert(card, syncSocial: false);
            }
          }
        }
        if (result.length < 200) break;
        after = (result.last as Map)['id'] as String;
      }
      return changed;
    } finally {
      _busy = false;
    }
  }
}
