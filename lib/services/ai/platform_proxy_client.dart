import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'system_proxy_client.dart';

http.Client createPlatformProxyClient() => SystemProxyClient((uri) async {
  if (Platform.isWindows) return resolveWindowsProxy(uri);
  if (Platform.isAndroid) {
    return await const MethodChannel(
          'ai_tavern/network',
        ).invokeMethod<String>('proxyForUrl', {'url': uri.origin}) ??
        'DIRECT';
  }
  return HttpClient.findProxyFromEnvironment(uri);
});
