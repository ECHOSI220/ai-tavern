import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/social_models.dart';
import '../../repositories/api_repository.dart';
import 'server_environment.dart';

class AccountClientService {
  AccountClientService({required this.apiRepository, http.Client? client})
    : _client = client ?? http.Client();

  final ApiRepository apiRepository;
  final http.Client _client;
  AuthTokens? tokens;
  String baseUrl = 'http://127.0.0.1:8765';
  String supabaseUrl = ServerEnvironment.supabaseUrl;
  String supabaseAnonKey = ServerEnvironment.supabaseAnonKey;

  bool get usesSupabase =>
      supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty;

  Future<AuthTokens?> restore() async {
    final raw = await apiRepository.readAccountTokens();
    if (raw.isEmpty) return null;
    try {
      tokens = AuthTokens.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
      if (tokens!.expiresAt.isBefore(DateTime.now())) {
        await refresh();
      }
      return tokens;
    } catch (_) {
      await apiRepository.writeAccountTokens('');
      tokens = null;
      return null;
    }
  }

  Future<AuthTokens> register({
    required String handle,
    required String displayName,
    required String password,
  }) => usesSupabase
      ? _supabasePasswordAuth(
          '/auth/v1/signup',
          email: handle,
          password: password,
          displayName: displayName,
        )
      : _auth('/api/auth/register', {
          'handle': handle,
          'displayName': displayName,
          'password': password,
          'deviceName': Platform.localHostname,
          'platform': Platform.operatingSystem,
        });

  Future<AuthTokens> login({
    required String handle,
    required String password,
  }) => usesSupabase
      ? _supabasePasswordAuth(
          '/auth/v1/token?grant_type=password',
          email: handle,
          password: password,
        )
      : _auth('/api/auth/login', {
          'handle': handle,
          'password': password,
          'deviceName': Platform.localHostname,
          'platform': Platform.operatingSystem,
        });

  Future<AuthTokens> refresh() async {
    final current = tokens;
    if (current == null) throw StateError('尚未登录');
    if (usesSupabase) {
      return _supabaseRefresh(current.refreshToken);
    }
    return _auth('/api/auth/refresh', {'refreshToken': current.refreshToken});
  }

  Future<void> logout() async {
    try {
      if (tokens != null && usesSupabase) {
        await _client.post(
          Uri.parse(
            '${supabaseUrl.replaceAll(RegExp(r'/$'), '')}/auth/v1/logout',
          ),
          headers: {
            'apikey': supabaseAnonKey,
            'Authorization': 'Bearer ${tokens!.accessToken}',
          },
        );
      } else if (tokens != null) {
        await post('/api/auth/logout', const {});
      }
    } finally {
      tokens = null;
      await apiRepository.writeAccountTokens('');
    }
  }

  Future<Map<String, Object?>> get(String path) => _request('GET', path);
  Future<Map<String, Object?>> post(String path, Map<String, Object?> body) =>
      _request('POST', path, body);

  /// Uses the signed-in user's JWT against Supabase PostgREST directly.
  /// Cloud saves do not need to make an extra Worker round trip.
  Future<Object?> supabaseRest(
    String method,
    String path, {
    Object? body,
    String? prefer,
  }) async {
    if (!usesSupabase || !path.startsWith('/')) {
      throw StateError('云数据库尚未配置');
    }
    var current = tokens;
    if (current == null) throw StateError('需要登录账号');

    Future<http.Response> send(String accessToken) {
      final headers = <String, String>{
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer $accessToken',
        if (body != null) 'Content-Type': 'application/json',
        'Prefer': ?prefer,
      };
      final uri = Uri.parse(
        '${supabaseUrl.replaceAll(RegExp(r'/$'), '')}/rest/v1$path',
      );
      return method == 'GET'
          ? _client.get(uri, headers: headers)
          : _client.post(uri, headers: headers, body: jsonEncode(body));
    }

    var response = await send(current.accessToken);
    if (response.statusCode == HttpStatus.unauthorized) {
      current = await refresh();
      response = await send(current.accessToken);
    }
    return _decodeAny(response);
  }

  Future<AuthTokens> _auth(String path, Map<String, Object?> body) async {
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final decoded = _decode(response);
    final value = AuthTokens.fromJson(decoded);
    tokens = value;
    await apiRepository.writeAccountTokens(jsonEncode(value.toJson()));
    return value;
  }

  Future<AuthTokens> _supabasePasswordAuth(
    String path, {
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await _client.post(
      Uri.parse('${supabaseUrl.replaceAll(RegExp(r'/$'), '')}$path'),
      headers: {'apikey': supabaseAnonKey, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        if (displayName != null) 'data': {'display_name': displayName.trim()},
      }),
    );
    return _saveSupabaseSession(_decode(response), fallbackEmail: email);
  }

  Future<AuthTokens> _supabaseRefresh(String refreshToken) async {
    final response = await _client.post(
      Uri.parse(
        '${supabaseUrl.replaceAll(RegExp(r'/$'), '')}/auth/v1/token?grant_type=refresh_token',
      ),
      headers: {'apikey': supabaseAnonKey, 'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );
    return _saveSupabaseSession(_decode(response));
  }

  Future<AuthTokens> _saveSupabaseSession(
    Map<String, Object?> json, {
    String fallbackEmail = '',
  }) async {
    final accessToken = json['access_token']?.toString() ?? '';
    final refreshToken = json['refresh_token']?.toString() ?? '';
    final rawUser = json['user'];
    final user = rawUser is Map
        ? rawUser.cast<String, Object?>()
        : const <String, Object?>{};
    if (accessToken.isEmpty || refreshToken.isEmpty || user['id'] == null) {
      throw StateError('注册成功但尚未获得登录会话，请完成邮箱验证后再登录');
    }
    final metadata = user['user_metadata'] is Map
        ? (user['user_metadata'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final email = user['email']?.toString() ?? fallbackEmail;
    final timestamp = DateTime.now();
    final value = AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: timestamp.add(
        Duration(seconds: (json['expires_in'] as num?)?.toInt() ?? 3600),
      ),
      deviceSessionId: 'supabase:${user['id']}',
      account: UserAccount(
        userId: user['id'].toString(),
        handle: email,
        displayName:
            metadata['display_name']?.toString() ?? email.split('@').first,
        createdAt:
            DateTime.tryParse(user['created_at']?.toString() ?? '') ??
            timestamp,
        lastOnlineAt: timestamp,
      ),
    );
    tokens = value;
    await apiRepository.writeAccountTokens(jsonEncode(value.toJson()));
    return value;
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, [
    Map<String, Object?> body = const {},
  ]) async {
    final current = tokens;
    if (current == null) throw StateError('需要登录账号');
    final uri = Uri.parse('$baseUrl$path');
    var response = method == 'GET'
        ? await _client.get(
            uri,
            headers: {'Authorization': 'Bearer ${current.accessToken}'},
          )
        : await _client.post(
            uri,
            headers: {
              'Authorization': 'Bearer ${current.accessToken}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          );
    if (response.statusCode == HttpStatus.unauthorized) {
      await refresh();
      final next = tokens!;
      response = method == 'GET'
          ? await _client.get(
              uri,
              headers: {'Authorization': 'Bearer ${next.accessToken}'},
            )
          : await _client.post(
              uri,
              headers: {
                'Authorization': 'Bearer ${next.accessToken}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(body),
            );
    }
    return _decode(response);
  }

  Map<String, Object?> _decode(http.Response response) {
    final value = _decodeAny(response);
    if (value is! Map) throw StateError('服务器返回的数据格式不正确');
    return value.cast<String, Object?>();
  }

  Object? _decodeAny(http.Response response) {
    Object? decoded;
    try {
      decoded = response.body.trim().isEmpty
          ? <String, Object?>{}
          : jsonDecode(response.body);
    } on FormatException {
      throw StateError('服务器返回了异常页面（HTTP ${response.statusCode}），请稍后重试');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final map = decoded is Map
          ? decoded.cast<String, Object?>()
          : const <String, Object?>{};
      final rawError = map['error'];
      final nested = rawError is Map ? rawError['message']?.toString() : null;
      throw StateError(
        nested ??
            map['msg']?.toString() ??
            map['message']?.toString() ??
            rawError?.toString() ??
            '请求失败（HTTP ${response.statusCode}）',
      );
    }
    return decoded;
  }

  void dispose() => _client.close();
}
