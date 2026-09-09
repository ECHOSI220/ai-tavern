import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../models/social_models.dart';
import 'social_backend_service.dart';

typedef CampaignSessionSnapshotProvider =
    Map<String, Object?>? Function(String campaignRoomId);
typedef CampaignSessionRestoreHandler =
    Future<void> Function(String campaignRoomId, Map<String, Object?> session);

class SocialHttpApi {
  SocialHttpApi({
    required this.backend,
    required this.assetDirectory,
    this.sessionSnapshotProvider,
    this.sessionRestoreHandler,
  });

  final SocialBackendService backend;
  final String assetDirectory;
  final CampaignSessionSnapshotProvider? sessionSnapshotProvider;
  final CampaignSessionRestoreHandler? sessionRestoreHandler;
  final _authLimiter = SlidingWindowRateLimiter(
    limit: 10,
    window: const Duration(minutes: 1),
  );
  final _socialLimiter = SlidingWindowRateLimiter(
    limit: 30,
    window: const Duration(minutes: 1),
  );

  Future<bool> handle(HttpRequest request) async {
    if (!request.uri.path.startsWith('/api/')) return false;
    _cors(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return true;
    }
    try {
      final path = request.uri.path;
      final body = await _body(request);
      if (path == '/api/auth/register' && request.method == 'POST') {
        _rate(_authLimiter, request, 'register');
        final tokens = await backend.register(
          handle: _required(body, 'handle'),
          displayName: body['displayName'] as String? ?? '',
          password: _required(body, 'password'),
          deviceName: body['deviceName'] as String? ?? 'Unknown Device',
          platform: body['platform'] as String? ?? 'unknown',
        );
        await _json(
          request.response,
          tokens.toJson(),
          status: HttpStatus.created,
        );
        return true;
      }
      if (path == '/api/auth/login' && request.method == 'POST') {
        _rate(_authLimiter, request, 'login');
        final tokens = await backend.login(
          handle: _required(body, 'handle'),
          password: _required(body, 'password'),
          deviceName: body['deviceName'] as String? ?? 'Unknown Device',
          platform: body['platform'] as String? ?? 'unknown',
        );
        await _json(request.response, tokens.toJson());
        return true;
      }
      if (path == '/api/auth/refresh' && request.method == 'POST') {
        _rate(_authLimiter, request, 'refresh');
        await _json(
          request.response,
          (await backend.refresh(_required(body, 'refreshToken'))).toJson(),
        );
        return true;
      }
      final identity = backend.authenticate(_bearer(request));
      final userId = identity.account.userId;
      _rate(_socialLimiter, request, userId);

      if (path == '/api/auth/logout' && request.method == 'POST') {
        await backend.logout(
          _bearer(request),
          allDevices: body['allDevices'] as bool? ?? false,
        );
        await _json(request.response, {'success': true});
        return true;
      }
      if (path == '/api/account/delete' && request.method == 'POST') {
        await backend.deleteAccount(userId);
        await _json(request.response, {'success': true});
        return true;
      }
      if (path == '/api/profile' && request.method == 'GET') {
        await _json(request.response, identity.account.toJson());
        return true;
      }
      if (path == '/api/devices' && request.method == 'GET') {
        await _json(request.response, {
          'devices': backend
              .devices(userId)
              .map(
                (value) => {
                  'id': value.id,
                  'deviceName': value.deviceName,
                  'platform': value.platform,
                  'lastSeenAt': value.lastSeenAt.toIso8601String(),
                  'supportsAIHost': value.supportsAIHost,
                  'providerTypes': value.providerTypes,
                  'toolCallingVerified': value.toolCallingVerified,
                },
              )
              .toList(),
        });
        return true;
      }
      if (path == '/api/devices/capability' && request.method == 'POST') {
        await backend.updateDeviceCapability(
          identity.deviceSession.id,
          supportsAIHost: body['supportsAIHost'] as bool? ?? false,
          providerTypes: (body['providerTypes'] as List? ?? const [])
              .map((value) => value.toString())
              .toList(),
          toolCallingVerified: body['toolCallingVerified'] as bool? ?? false,
        );
        await _json(request.response, {'success': true});
        return true;
      }
      if (path == '/api/users/search' && request.method == 'GET') {
        await _json(request.response, {
          'users': backend
              .searchUsers(userId, request.uri.queryParameters['handle'] ?? '')
              .map((value) => value.toJson())
              .toList(),
        });
        return true;
      }
      if (path == '/api/friends' && request.method == 'GET') {
        await _json(request.response, {'friends': backend.friends(userId)});
        return true;
      }
      if (path == '/api/friends/request' && request.method == 'POST') {
        await _json(
          request.response,
          (await backend.requestFriend(
            userId,
            _required(body, 'handle'),
          )).toJson(),
          status: HttpStatus.created,
        );
        return true;
      }
      if (path == '/api/friends/respond' && request.method == 'POST') {
        await _json(
          request.response,
          (await backend.respondFriend(
            userId,
            _required(body, 'friendshipId'),
            accept: body['accept'] as bool? ?? false,
          )).toJson(),
        );
        return true;
      }
      if (path == '/api/friends/block' && request.method == 'POST') {
        await backend.block(userId, _required(body, 'userId'));
        await _json(request.response, {'success': true});
        return true;
      }
      if (path == '/api/recent-players' && request.method == 'GET') {
        await _json(request.response, {
          'players': backend
              .recentPlayers(userId)
              .map((value) => value.toJson())
              .toList(),
        });
        return true;
      }
      if (path == '/api/campaigns' && request.method == 'GET') {
        await _json(request.response, {
          'campaigns': backend
              .campaignsFor(userId)
              .map((value) => value.toJson())
              .toList(),
        });
        return true;
      }
      if (path == '/api/campaigns' && request.method == 'POST') {
        final privacy =
            CampaignRoomPrivacy.values
                .where((value) => value.name == body['privacy'])
                .firstOrNull ??
            CampaignRoomPrivacy.inviteOnly;
        await _json(
          request.response,
          (await backend.createCampaign(
            ownerUserId: userId,
            campaignId: _required(body, 'campaignId'),
            title: _required(body, 'title'),
            description: body['description'] as String? ?? '',
            maxMembers: (body['maxMembers'] as num?)?.toInt() ?? 6,
            privacy: privacy,
          )).toJson(),
          status: HttpStatus.created,
        );
        return true;
      }
      final campaignMatch = RegExp(
        r'^/api/campaigns/([^/]+)$',
      ).firstMatch(path);
      if (campaignMatch != null && request.method == 'GET') {
        final id = campaignMatch.group(1)!;
        await _json(request.response, {
          'campaign': backend.campaignFor(userId, id).toJson(),
          'session': sessionSnapshotProvider?.call(id),
        });
        return true;
      }
      final campaignAction = RegExp(
        r'^/api/campaigns/([^/]+)/(invite|bind-character|announcement|archive|backup|restore|host-policy|member-role|transfer-owner|member|delete)$',
      ).firstMatch(path);
      if (campaignAction != null && request.method == 'POST') {
        final id = campaignAction.group(1)!;
        switch (campaignAction.group(2)!) {
          case 'invite':
            await _json(
              request.response,
              (await backend.inviteCampaign(
                userId,
                id,
                _required(body, 'handle'),
              )).toJson(),
            );
          case 'bind-character':
            await _json(
              request.response,
              (await backend.bindCharacter(
                userId,
                id,
                _required(body, 'characterId'),
                expectedRevision:
                    (body['expectedRevision'] as num?)?.toInt() ?? -1,
              )).toJson(),
            );
          case 'announcement':
            await _json(
              request.response,
              (await backend.announce(
                userId,
                id,
                _required(body, 'text'),
              )).toJson(),
            );
          case 'archive':
            await _json(
              request.response,
              (await backend.archive(
                userId,
                id,
                finalSummary: body['finalSummary'] as String? ?? '',
              )).toJson(),
            );
          case 'backup':
            final session = sessionSnapshotProvider?.call(id);
            if (session == null) throw StateError('战役尚无可备份 Session');
            await _json(request.response, {
              'backupId': await backend.createBackup(userId, id, session),
            });
          case 'restore':
            final session = await backend.restoreBackup(
              userId,
              id,
              _required(body, 'backupId'),
            );
            await sessionRestoreHandler?.call(id, session);
            await _json(request.response, {
              'session': session,
              'forceResync': true,
            });
          case 'host-policy':
            await _json(
              request.response,
              (await backend.updateHostPolicy(
                userId,
                id,
                AIHostPolicy.fromJson(body),
              )).toJson(),
            );
          case 'member-role':
            final role = CampaignMemberRole.values
                .where((value) => value.name == body['role'])
                .first;
            await _json(
              request.response,
              (await backend.setMemberRole(
                userId,
                id,
                _required(body, 'userId'),
                role,
              )).toJson(),
            );
          case 'transfer-owner':
            await _json(
              request.response,
              (await backend.requestOwnershipTransfer(
                userId,
                id,
                _required(body, 'userId'),
              )).toJson(),
            );
          case 'member':
            await _json(
              request.response,
              (await backend.manageMember(
                userId,
                id,
                _required(body, 'userId'),
                ban: body['ban'] as bool? ?? false,
              )).toJson(),
            );
          case 'delete':
            await _json(
              request.response,
              (await backend.softDeleteCampaign(userId, id)).toJson(),
            );
        }
        return true;
      }
      if (path == '/api/invites' && request.method == 'GET') {
        await _json(request.response, {
          'invites': backend
              .invitesFor(userId)
              .map((value) => value.toJson())
              .toList(),
        });
        return true;
      }
      if (path == '/api/invites/respond' && request.method == 'POST') {
        final inviteId = _required(body, 'inviteId');
        final invite = backend
            .invitesFor(userId)
            .where((value) => value.id == inviteId)
            .firstOrNull;
        await _json(
          request.response,
          (invite?.type == SocialInviteType.ownershipTransfer
                  ? await backend.respondOwnershipTransfer(
                      userId,
                      inviteId,
                      accept: body['accept'] as bool? ?? false,
                    )
                  : await backend.respondCampaignInvite(
                      userId,
                      inviteId,
                      accept: body['accept'] as bool? ?? false,
                    ))
              .toJson(),
        );
        return true;
      }
      if (path == '/api/notifications' && request.method == 'GET') {
        await _json(request.response, {
          'notifications': backend
              .notifications(userId)
              .map((value) => value.toJson())
              .toList(),
        });
        return true;
      }
      if (path == '/api/notifications/read' && request.method == 'POST') {
        await backend.readNotification(userId, _required(body, 'id'));
        await _json(request.response, {'success': true});
        return true;
      }
      if (path == '/api/assets' && request.method == 'POST') {
        final bytes = base64Decode(_required(body, 'base64'));
        if (bytes.length > 10 * 1024 * 1024) throw StateError('资源不能超过 10MB');
        final digest = sha256.convert(bytes).toString();
        final extension = (body['extension'] as String? ?? 'bin').replaceAll(
          RegExp('[^a-zA-Z0-9]'),
          '',
        );
        final assetDir = Directory(assetDirectory);
        await assetDir.create(recursive: true);
        final file = File(
          '${assetDir.path}${Platform.pathSeparator}$digest.$extension',
        );
        final alreadyExists = await file.exists();
        if (!alreadyExists) await file.writeAsBytes(bytes, flush: true);
        await _json(request.response, {
          'assetId': digest,
          'path': '/api/assets/$digest.$extension',
          'deduplicated': alreadyExists,
        });
        return true;
      }
      request.response.statusCode = HttpStatus.notFound;
      await _json(request.response, {'error': 'not_found'});
    } catch (error) {
      final status = error is FormatException
          ? HttpStatus.badRequest
          : error.toString().contains('Token')
          ? HttpStatus.unauthorized
          : error.toString().contains('Rate')
          ? HttpStatus.tooManyRequests
          : HttpStatus.badRequest;
      await _json(request.response, {
        'error': error.toString(),
      }, status: status);
    }
    return true;
  }

  void _rate(
    SlidingWindowRateLimiter limiter,
    HttpRequest request,
    String key,
  ) {
    final ip = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    if (!limiter.allow('$ip:$key')) throw StateError('Rate limit exceeded');
  }

  Future<Map<String, Object?>> _body(HttpRequest request) async {
    if (request.method == 'GET' || request.method == 'DELETE') return {};
    final text = await utf8.decoder.bind(request).join();
    if (text.trim().isEmpty) return {};
    return (jsonDecode(text) as Map).cast<String, Object?>();
  }

  String _bearer(HttpRequest request) {
    final value = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (!value.startsWith('Bearer ')) throw StateError('缺少 Access Token');
    return value.substring(7).trim();
  }

  String _required(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key 不能为空');
    }
    return value.trim();
  }

  Future<void> _json(
    HttpResponse response,
    Object value, {
    int status = HttpStatus.ok,
  }) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(value));
    await response.close();
  }

  void _cors(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Headers', 'Authorization, Content-Type')
      ..set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  }
}
