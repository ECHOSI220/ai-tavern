import 'package:uuid/uuid.dart';
import '../../models/trpg_models.dart';

/// A personal branch uses only the information already visible to this player.
class MultiplayerArchiveService {
  static TRPGSession toSolo(TRPGSession archive) {
    final playerId = archive.metadata['localPlayerId'];
    final human = archive.players.where((p) => p.playerId == playerId).firstOrNull;
    final character = archive.playerCharacters.where((p) => p.playerId == playerId).firstOrNull;
    if (human == null || character == null) {
      throw StateError('这份记录没有你的角色，暂时不能转为单人');
    }
    final raw = archive.toJson();
    raw['id'] = const Uuid().v4();
    raw['title'] = '${archive.title} · 单人分支';
    raw['mode'] = 'solo';
    raw['status'] = 'active';
    raw['gmProviderConfigRef'] = null;
    raw['roomOwnerPlayerId'] = playerId;
    raw['players'] = [
      human.copyWith(isAiControlled: false).toJson(),
      ...archive.players.where((p) => p.playerId != playerId && p.characterId != null)
          .map((p) => p.copyWith(isAiControlled: true).toJson()),
    ];
    raw['playerCharacters'] = [character.toJson(), ...archive.playerCharacters.where((p) => p.id != character.id).map((p) => p.toJson())];
    raw['metadata'] = {...archive.metadata, 'localMultiplayerArchive': false, 'sourceArchiveId': archive.id};
    raw['updatedAt'] = DateTime.now().toIso8601String();
    raw['lastPlayedAt'] = raw['updatedAt'];
    return TRPGSession.fromJson(raw);
  }
}
