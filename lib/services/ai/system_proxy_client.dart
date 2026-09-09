import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

typedef ProxyResolver = Future<String> Function(Uri uri);

/// Resolve the OS route before sending any request bytes. Never replay a POST.
class SystemProxyClient extends http.BaseClient {
  SystemProxyClient(this.resolve);
  final ProxyResolver resolve;
  final Set<http.Client> _clients = {};
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final route = await resolve(
      request.url,
    ).timeout(const Duration(seconds: 5));
    if (_closed) throw http.ClientException('Request cancelled');
    final client = IOClient(HttpClient()..findProxy = (_) => route);
    _clients.add(client);
    return client.send(request);
  }

  @override
  void close() {
    _closed = true;
    for (final client in _clients) {
      client.close();
    }
    _clients.clear();
  }
}

String windowsProxyRoute(Uri uri, Map<String, String> settings) {
  if (settings['ProxyEnable'] != '0x1') return 'DIRECT';
  final bypass = (settings['ProxyOverride'] ?? '').split(';');
  for (final item in bypass) {
    if (item == '<local>' && !uri.host.contains('.')) return 'DIRECT';
    if (item.isNotEmpty &&
        RegExp(
          '^${RegExp.escape(item).replaceAll(r'\*', '.*')}'
          r'$',
          caseSensitive: false,
        ).hasMatch(uri.host))
      return 'DIRECT';
  }
  final server = settings['ProxyServer'] ?? '';
  String? address;
  if (!server.contains('=')) {
    address = server;
  } else {
    for (final part in server.split(';')) {
      if (part.startsWith('${uri.scheme}='))
        address = part.substring(uri.scheme.length + 1);
    }
  }
  if (address == null || address.isEmpty) return 'DIRECT';
  final parsed = Uri.tryParse(
    address.contains('://') ? address : 'http://$address',
  );
  if (parsed == null ||
      parsed.host.isEmpty ||
      parsed.userInfo.isNotEmpty ||
      !parsed.hasPort) {
    throw const FormatException('System proxy address is invalid');
  }
  return 'PROXY ${parsed.host}:${parsed.port}';
}

Future<String> resolveWindowsProxy(Uri uri) async {
  final result = await Process.run('reg.exe', [
    'query',
    r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
  ]);
  if (result.exitCode != 0)
    throw const HttpException('Cannot read system proxy settings');
  final settings = <String, String>{};
  for (final line in result.stdout.toString().split('\n')) {
    final match = RegExp(
      r'^\s*(ProxyEnable|ProxyServer|ProxyOverride)\s+REG_\w+\s+(.*?)\s*$',
    ).firstMatch(line);
    if (match != null) settings[match[1]!] = match[2]!;
  }
  return windowsProxyRoute(uri, settings);
}
