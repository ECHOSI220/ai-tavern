import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tavern/services/trpg/multiplayer_transport.dart';

class _Socket extends Stream<dynamic> implements WebSocket {
  final controller = StreamController<dynamic>();
  @override
  int readyState = WebSocket.open;
  @override
  int? closeCode;
  @override
  Duration? pingInterval;
  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  Future<void> close([int? code, String? reason]) async {
    readyState = WebSocket.closed;
    closeCode = code;
    unawaited(controller.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'public drop reconnects; explicit exit cancels pending retries',
    () async {
      final sockets = <_Socket>[];
      final transport = WebSocketTransport(
        connector: (_) {
          final socket = _Socket();
          sockets.add(socket);
          return socket;
        },
      );
      await transport.connect('wss://game.invalid/v1/rooms/test/socket');
      await sockets.first.close(1006);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(transport.isConnected, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(sockets, hasLength(2));
      expect(transport.isConnected, isTrue);
      await sockets.last.close(1006);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await transport.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(sockets, hasLength(2));
      expect(transport.isConnected, isFalse);
    },
  );

  test('server room closure does not reconnect', () async {
    final sockets = <_Socket>[];
    final transport = WebSocketTransport(
      connector: (_) {
        final socket = _Socket();
        sockets.add(socket);
        return socket;
      },
    );
    await transport.connect('wss://game.invalid/v1/rooms/test/socket');
    await sockets.first.close(1000, 'room_closed');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(sockets, hasLength(1));
    await transport.disconnect();
  });

  test('Supabase relay room sockets also reconnect', () async {
    final sockets = <_Socket>[];
    final transport = WebSocketTransport(
      connector: (_) {
        final socket = _Socket();
        sockets.add(socket);
        return socket;
      },
    );
    await transport.connect(
      'wss://project.supabase.co/functions/v1/game-server-proxy/'
      'v1/rooms/test/socket',
    );
    await sockets.first.close(1006);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(sockets, hasLength(2));
    await transport.disconnect();
  });
}
