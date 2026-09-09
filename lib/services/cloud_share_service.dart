import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/character.dart';
import '../models/story_card.dart';
import 'trpg/account_client_service.dart';

class CloudShareService {
  CloudShareService(this.account, {http.Client? client})
    : _client = client ?? http.Client();
  final AccountClientService account;
  final http.Client _client;
  static const website = 'https://ai-tavern-cloud.pages.dev';
  static Map<String, Object?> characterData(Character c) => {
    'name': c.name,
    'description': c.description,
    'personality': c.personality,
    'appearance': c.appearance,
    'background': c.background,
    'speakingStyle': c.speakingStyle,
    'goals': c.goals,
    'exampleDialogue': c.exampleDialogue,
  };
  static Map<String, Object?> characterPackage(Character c) => {
    'schemaVersion': 1,
    'contentType': 'CHARACTER_CARD',
    'data': characterData(c),
  };
  static Map<String, Object?> storyPackage(StoryCard card) => {
    'schemaVersion': 1,
    'contentType': 'CAMPAIGN_TEMPLATE',
    'data': {
      'format': 'tavern-story-template',
      'name': card.name,
      'description': card.description,
      'scenario': card.template.scenario,
      'worldSetting': card.template.worldSetting,
      'openingMessage': card.template.openingMessage,
      'characters': card.template.characters.map(characterData).toList(),
    },
  };
  static String encode(Map<String, Object?> package) {
    if (package['schemaVersion'] != 1 || package['data'] is! Map) {
      throw const FormatException('无效的分享包');
    }
    final encoded = jsonEncode(package);
    if (utf8.encode(encoded).length > 2000000) {
      throw const FormatException('分享内容超过 2 MB');
    }
    final sensitive = RegExp(
      r'api.?key|token|password|secret|credential|authorization|private.?chat|private.?roll|gm.?secret|session|message.?history|local.?path',
      caseSensitive: false,
    );
    void inspect(Object? value, int depth) {
      if (depth > 32) throw const FormatException('分享包嵌套过深');
      if (value is Map) {
        for (final entry in value.entries) {
          if (sensitive.hasMatch(entry.key.toString())) {
            throw const FormatException('分享包包含敏感字段');
          }
          inspect(entry.value, depth + 1);
        }
      } else if (value is List) {
        for (final child in value) {
          inspect(child, depth + 1);
        }
      } else if (value is String &&
          (RegExp(
                r'^(file:|[a-z]:\\|/Users/|/home/)',
                caseSensitive: false,
              ).hasMatch(value) ||
              RegExp(
                r'\b(sk-[a-zA-Z0-9]{16,}|eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.)',
              ).hasMatch(value))) {
        throw const FormatException('内容中含本地路径或疑似密钥，请检查后上传');
      }
    }

    inspect(package['data'], 0);
    return encoded;
  }

  Future<String> upload({
    required Map<String, Object?> package,
    required String title,
    required String description,
    String visibility = 'PRIVATE',
  }) async {
    if (!const ['PRIVATE', 'UNLISTED', 'PUBLIC'].contains(visibility)) {
      throw ArgumentError('可见性无效');
    }
    final encoded = encode(package);
    final tokens = account.tokens ?? await account.restore();
    if (tokens == null || !account.usesSupabase) throw StateError('请先登录云端账号');
    if (tokens.expiresAt.isBefore(
      DateTime.now().add(const Duration(minutes: 1)),
    )) {
      await account.refresh();
    }
    final id = const Uuid().v4();
    final path = '${account.tokens!.account.userId}/$id/1.json';
    final uri = Uri.parse(
      '${account.supabaseUrl}/storage/v1/object/shared-content/$path',
    );
    Future<http.Response> send() => _client
        .post(
          uri,
          headers: {
            'apikey': account.supabaseAnonKey,
            'Authorization': 'Bearer ${account.tokens!.accessToken}',
            'Content-Type': 'application/json',
            'x-upsert': 'false',
          },
          body: utf8.encode(encoded),
        )
        .timeout(const Duration(seconds: 25));
    var response = await send();
    if (response.statusCode == 401) {
      await account.refresh();
      response = await send();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('上传文件失败（HTTP ${response.statusCode}），请稍后重试');
    }
    try {
      await account
          .supabaseRest(
            'POST',
            '/rpc/cloud_publish_share',
            body: {
              'share_id': id,
              'share_title': title.trim(),
              'share_description': description.trim(),
              'share_type': package['contentType'],
              'share_visibility': visibility,
              'share_tags': <String>[],
              'object_path': path,
              'object_size': utf8.encode(encoded).length,
              'object_checksum': sha256
                  .convert(utf8.encode(encoded))
                  .toString(),
            },
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      // A lost HTTP acknowledgement may still have committed. Check before retrying.
      final existing = await account
          .supabaseRest(
            'POST',
            '/rpc/cloud_share_by_id',
            body: {'share_id': id},
          )
          .timeout(const Duration(seconds: 15));
      if (existing is! Map || existing['content'] is! Map) {
        throw StateError('文件已上传，但发布未确认。请在网页“我的创作”检查；编号 $id');
      }
    }
    return '$website/share/$id';
  }

  void dispose() => _client.close();
}
