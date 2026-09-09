import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

/// 只记录运行状态和短元数据，不记录 API Key、Prompt 或完整聊天正文。
abstract final class AppLogger {
  static bool _debugEnabled = false;
  static File? _diagnosticFile;
  static Future<void> _pendingWrite = Future<void>.value();

  static void setDiagnosticDirectory(String path) {
    _diagnosticFile = File('$path${Platform.pathSeparator}diagnostics.log');
  }

  static bool get debugEnabled => _debugEnabled;

  static void configure({required bool debugEnabled}) {
    _debugEnabled = debugEnabled;
    info('logger.configured', fields: {'debug': debugEnabled});
  }

  static void info(String event, {Map<String, Object?> fields = const {}}) {
    _write('INFO', event, fields: fields);
  }

  static void debug(String event, {Map<String, Object?> fields = const {}}) {
    if (!_debugEnabled) return;
    _write('DEBUG', event, fields: fields);
  }

  static void error(
    String event,
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    _write(
      'ERROR',
      event,
      fields: {...fields, 'errorType': error.runtimeType.toString()},
      error: error,
      stackTrace: _debugEnabled ? stackTrace : null,
    );
  }

  static void _write(
    String level,
    String event, {
    required Map<String, Object?> fields,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final record = <String, Object?>{
      'level': level,
      'event': event,
      if (fields.isNotEmpty) 'fields': _sanitize(fields),
    };
    final message = jsonEncode(record);
    final file = _diagnosticFile;
    if (file != null &&
        (event.startsWith('ai.tools.') ||
            event.startsWith('multiplayer.ai.'))) {
      _pendingWrite = _pendingWrite
          .then((_) async {
            if (await file.exists() && await file.length() > 1048576) {
              await file.rename('${file.path}.previous');
            }
            await file.writeAsString(
              '${DateTime.now().toUtc().toIso8601String()} $message\n',
              mode: FileMode.append,
            );
          })
          .catchError((Object _) {});
    }
    developer.log(
      message,
      name: 'ai_tavern',
      error: error,
      stackTrace: stackTrace,
    );
    assert(() {
      // ignore: avoid_print
      print('[ai_tavern] $message');
      return true;
    }());
  }

  static Map<String, Object?> _sanitize(Map<String, Object?> fields) {
    const sensitiveFragments = <String>{
      'apikey',
      'authorization',
      'content',
      'messages',
      'prompt',
      'body',
    };
    return fields.map((key, value) {
      final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (sensitiveFragments.any(normalized.contains)) {
        return MapEntry(key, '[redacted]');
      }
      final safeValue = value is String && value.length > 200
          ? '${value.substring(0, 200)}…'
          : value;
      return MapEntry(key, safeValue);
    });
  }
}
