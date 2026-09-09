import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tavern/services/ai/system_proxy_client.dart';

void main() {
  final uri = Uri.parse('https://api.deepseek.com/chat/completions');
  test('Windows enabled proxy is used, disabled proxy is not', () {
    expect(
      windowsProxyRoute(uri, {
        'ProxyEnable': '0x1',
        'ProxyServer': '127.0.0.1:7897',
      }),
      'PROXY 127.0.0.1:7897',
    );
    expect(
      windowsProxyRoute(uri, {
        'ProxyEnable': '0x0',
        'ProxyServer': '127.0.0.1:7897',
      }),
      'DIRECT',
    );
  });
  test('protocol specific proxy and bypass rules are respected', () {
    final settings = {
      'ProxyEnable': '0x1',
      'ProxyServer': 'http=localhost:80;https=localhost:81',
      'ProxyOverride': '*.internal;<local>',
    };
    expect(windowsProxyRoute(uri, settings), 'PROXY localhost:81');
    expect(
      windowsProxyRoute(Uri.parse('https://game.internal'), settings),
      'DIRECT',
    );
    expect(
      windowsProxyRoute(Uri.parse('http://localgame'), settings),
      'DIRECT',
    );
  });
}
