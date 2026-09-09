import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../models/nearby_models.dart';

abstract interface class ProximityConnectionsManager {
  Stream<NearbyPlatformEvent> get events;
  bool isEndpointConnected(String endpointId);
  Future<NearbySupportState> supportState();
  Future<NearbyPermissionState> permissionState();
  Future<NearbyPermissionState> requestPermissions();
  Future<void> openSettings();
  Future<void> startAdvertising({
    required String endpointName,
    required String roomName,
  });
  Future<void> stopAdvertising();
  Future<void> startDiscovery();
  Future<void> stopDiscovery();
  Future<void> requestConnection(String endpointId, String playerName);
  Future<void> acceptConnection(String endpointId);
  Future<void> rejectConnection(String endpointId);
  Future<void> sendBytes(String endpointId, Uint8List bytes);
  Future<int?> sendFile(String endpointId, String path);
  Future<void> disconnectEndpoint(String endpointId);
  Future<void> disconnectAll();
}

class NearbyConnectionsManager implements ProximityConnectionsManager {
  NearbyConnectionsManager._() {
    if (Platform.isAndroid) {
      _eventChannel.receiveBroadcastStream().listen((raw) {
        if (raw is! Map) return;
        final event = NearbyPlatformEvent.fromJson(raw);
        if (event.type == 'connected') {
          _connected.add(event.data['endpointId']?.toString() ?? '');
        } else if (event.type == 'disconnected' ||
            event.type == 'connectionFailed') {
          _connected.remove(event.data['endpointId']?.toString() ?? '');
        }
        _events.add(event);
      }, onError: _events.addError);
    }
  }

  static final instance = NearbyConnectionsManager._();
  static const _methodChannel = MethodChannel('ai_tavern/nearby_connections');
  static const _eventChannel = EventChannel(
    'ai_tavern/nearby_connections_events',
  );

  final _events = StreamController<NearbyPlatformEvent>.broadcast();
  final _connected = <String>{};
  @override
  Stream<NearbyPlatformEvent> get events => _events.stream;
  @override
  bool isEndpointConnected(String endpointId) =>
      _connected.contains(endpointId);

  @override
  Future<NearbySupportState> supportState() async {
    if (!Platform.isAndroid) {
      return const NearbySupportState(
        platformSupported: false,
        playServicesAvailable: false,
      );
    }
    final value = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'isSupported',
    );
    return NearbySupportState.fromJson(value ?? const {});
  }

  @override
  Future<NearbyPermissionState> permissionState() async {
    if (!Platform.isAndroid) {
      return const NearbyPermissionState(granted: false);
    }
    final value = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'permissionState',
    );
    return NearbyPermissionState.fromJson(value ?? const {});
  }

  @override
  Future<NearbyPermissionState> requestPermissions() async {
    final value = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'requestPermissions',
    );
    return NearbyPermissionState.fromJson(value ?? const {});
  }

  @override
  Future<void> openSettings() => _methodChannel.invokeMethod('openSettings');

  @override
  Future<void> startAdvertising({
    required String endpointName,
    required String roomName,
  }) => _methodChannel.invokeMethod('startAdvertising', {
    'endpointName': endpointName,
    'roomName': roomName,
  });

  @override
  Future<void> stopAdvertising() =>
      _methodChannel.invokeMethod('stopAdvertising');
  @override
  Future<void> startDiscovery() =>
      _methodChannel.invokeMethod('startDiscovery');
  @override
  Future<void> stopDiscovery() => _methodChannel.invokeMethod('stopDiscovery');
  @override
  Future<void> requestConnection(String endpointId, String playerName) =>
      _methodChannel.invokeMethod('requestConnection', {
        'endpointId': endpointId,
        'playerName': playerName,
      });
  @override
  Future<void> acceptConnection(String endpointId) => _methodChannel
      .invokeMethod('acceptConnection', {'endpointId': endpointId});
  @override
  Future<void> rejectConnection(String endpointId) => _methodChannel
      .invokeMethod('rejectConnection', {'endpointId': endpointId});
  @override
  Future<void> sendBytes(String endpointId, Uint8List bytes) => _methodChannel
      .invokeMethod('sendBytes', {'endpointId': endpointId, 'bytes': bytes});
  @override
  Future<int?> sendFile(String endpointId, String path) => _methodChannel
      .invokeMethod<int>('sendFile', {'endpointId': endpointId, 'path': path});
  @override
  Future<void> disconnectEndpoint(String endpointId) => _methodChannel
      .invokeMethod('disconnectEndpoint', {'endpointId': endpointId});
  @override
  Future<void> disconnectAll() async {
    _connected.clear();
    await _methodChannel.invokeMethod('disconnectAll');
  }
}

class WifiDirectConnectionsManager implements ProximityConnectionsManager {
  WifiDirectConnectionsManager._() {
    if (Platform.isAndroid) {
      _eventChannel.receiveBroadcastStream().listen((raw) {
        if (raw is! Map) return;
        final event = NearbyPlatformEvent.fromJson(raw);
        if (event.type == 'connected') {
          _connected.add(event.data['endpointId']?.toString() ?? '');
        } else if (event.type == 'disconnected' ||
            event.type == 'connectionFailed') {
          _connected.remove(event.data['endpointId']?.toString() ?? '');
        }
        _events.add(event);
      }, onError: _events.addError);
    }
  }

  static final instance = WifiDirectConnectionsManager._();
  static const _methodChannel = MethodChannel('ai_tavern/wifi_direct');
  static const _eventChannel = EventChannel('ai_tavern/wifi_direct_events');
  final _events = StreamController<NearbyPlatformEvent>.broadcast();
  final _connected = <String>{};

  @override
  Stream<NearbyPlatformEvent> get events => _events.stream;
  @override
  bool isEndpointConnected(String endpointId) =>
      _connected.contains(endpointId);

  @override
  Future<NearbySupportState> supportState() async {
    if (!Platform.isAndroid) {
      return const NearbySupportState(
        platformSupported: false,
        playServicesAvailable: false,
        backend: 'wifiDirect',
      );
    }
    final value = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'isSupported',
    );
    return NearbySupportState.fromJson(value ?? const {});
  }

  @override
  Future<NearbyPermissionState> permissionState() async =>
      NearbyPermissionState.fromJson(
        await _methodChannel.invokeMapMethod<Object?, Object?>(
              'permissionState',
            ) ??
            const {},
      );

  @override
  Future<NearbyPermissionState> requestPermissions() async =>
      NearbyPermissionState.fromJson(
        await _methodChannel.invokeMapMethod<Object?, Object?>(
              'requestPermissions',
            ) ??
            const {},
      );

  @override
  Future<void> openSettings() => _methodChannel.invokeMethod('openSettings');
  @override
  Future<void> startAdvertising({
    required String endpointName,
    required String roomName,
  }) => _methodChannel.invokeMethod('startAdvertising', {
    'endpointName': endpointName,
    'roomName': roomName,
  });
  @override
  Future<void> stopAdvertising() =>
      _methodChannel.invokeMethod('stopAdvertising');
  @override
  Future<void> startDiscovery() =>
      _methodChannel.invokeMethod('startDiscovery');
  @override
  Future<void> stopDiscovery() => _methodChannel.invokeMethod('stopDiscovery');
  @override
  Future<void> requestConnection(String endpointId, String playerName) =>
      _methodChannel.invokeMethod('requestConnection', {
        'endpointId': endpointId,
        'playerName': playerName,
      });
  @override
  Future<void> acceptConnection(String endpointId) => _methodChannel
      .invokeMethod('acceptConnection', {'endpointId': endpointId});
  @override
  Future<void> rejectConnection(String endpointId) => _methodChannel
      .invokeMethod('rejectConnection', {'endpointId': endpointId});
  @override
  Future<void> sendBytes(String endpointId, Uint8List bytes) => _methodChannel
      .invokeMethod('sendBytes', {'endpointId': endpointId, 'bytes': bytes});
  @override
  Future<int?> sendFile(String endpointId, String path) => _methodChannel
      .invokeMethod<int>('sendFile', {'endpointId': endpointId, 'path': path});
  @override
  Future<void> disconnectEndpoint(String endpointId) => _methodChannel
      .invokeMethod('disconnectEndpoint', {'endpointId': endpointId});
  @override
  Future<void> disconnectAll() async {
    _connected.clear();
    await _methodChannel.invokeMethod('disconnectAll');
  }
}
