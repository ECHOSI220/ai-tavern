import 'dart:async';

import '../../models/trpg_models.dart';
import '../../repositories/trpg_session_repository.dart';

class TRPGSaveQueue {
  TRPGSaveQueue(
    this._repository, {
    this.debounce = const Duration(milliseconds: 250),
  });

  final TRPGSessionRepository _repository;
  final Duration debounce;
  Timer? _timer;
  TRPGSession? _pending;
  Completer<void>? _completer;

  Future<void> enqueue(TRPGSession session) {
    _pending = session;
    _timer?.cancel();
    _completer ??= Completer<void>();
    _timer = Timer(debounce, _flushInternal);
    return _completer!.future;
  }

  Future<void> flush() async {
    _timer?.cancel();
    await _flushInternal();
  }

  Future<void> _flushInternal() async {
    final session = _pending;
    _pending = null;
    if (session != null) await _repository.upsert(session);
    final completer = _completer;
    _completer = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  Future<void> dispose() async {
    await flush();
    _timer = null;
  }
}
