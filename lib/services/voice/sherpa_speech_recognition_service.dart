import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../models/voice_settings.dart';
import 'voice_model_manager.dart';
import 'voice_types.dart';

abstract interface class SpeechRecognitionService {
  SpeechRecognitionState get state;
  Stream<SpeechRecognitionState> get states;
  Stream<String> get partialText;
  Future<void> initialize(SpeechLanguageMode language);
  Future<void> startListening({required VoiceSettings settings});
  Future<SpeechRecognitionResult?> stopListening();
  Future<void> cancelListening();
  Future<void> pauseListening();
  Future<void> resumeListening();
  Future<void> dispose();
}

class SherpaSpeechRecognitionService implements SpeechRecognitionService {
  SherpaSpeechRecognitionService(this._models);

  final VoiceModelManager _models;
  final AudioRecorder _recorder = AudioRecorder();
  final _stateController = StreamController<SpeechRecognitionState>.broadcast();
  final _partialController = StreamController<String>.broadcast();
  final _samples = <double>[];
  StreamSubscription<Uint8List>? _recording;
  sherpa.OfflineRecognizer? _recognizer;
  sherpa.VoiceActivityDetector? _vad;
  SpeechRecognitionState _state = SpeechRecognitionState.idle;
  SpeechRecognitionResult? _result;
  VoiceSettings _settings = const VoiceSettings();
  bool _speechSeen = false;
  bool _stopping = false;

  @override
  SpeechRecognitionState get state => _state;

  @override
  Stream<SpeechRecognitionState> get states => _stateController.stream;

  @override
  Stream<String> get partialText => _partialController.stream;

  void _setState(SpeechRecognitionState value) {
    _state = value;
    _stateController.add(value);
  }

  @override
  Future<void> initialize(SpeechLanguageMode language) async {
    if (_recognizer != null) return;
    _setState(SpeechRecognitionState.loading);
    final asrStatus = await _models.status(VoiceModelManager.senseVoice);
    final vadStatus = await _models.status(VoiceModelManager.sileroVad);
    if (!asrStatus.installed || !vadStatus.installed) {
      _setState(SpeechRecognitionState.error);
      throw const VoiceModelMissingException('尚未安装语音识别模型或 VAD 模型。');
    }
    final model = await _models.filePath(
      VoiceModelManager.senseVoice,
      'model.int8.onnx',
    );
    final tokens = await _models.filePath(
      VoiceModelManager.senseVoice,
      'tokens.txt',
    );
    final vad = await _models.filePath(
      VoiceModelManager.sileroVad,
      'silero_vad.onnx',
    );
    sherpa.initBindings();
    final languageCode = switch (language) {
      SpeechLanguageMode.chinese => 'zh',
      SpeechLanguageMode.english => 'en',
      SpeechLanguageMode.auto => 'auto',
    };
    _recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          senseVoice: sherpa.OfflineSenseVoiceModelConfig(
            model: model!,
            language: languageCode,
            useInverseTextNormalization: true,
          ),
          tokens: tokens!,
          numThreads: 2,
          debug: false,
        ),
      ),
    );
    _vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: vad!,
          threshold: _settings.vadThreshold,
          minSilenceDuration: _settings.speechEndSilenceSeconds,
          minSpeechDuration: 0.25,
          maxSpeechDuration: _settings.maxRecordingSeconds.toDouble(),
        ),
        sampleRate: 16000,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: _settings.maxRecordingSeconds.toDouble(),
    );
    _setState(SpeechRecognitionState.idle);
  }

  @override
  Future<void> startListening({required VoiceSettings settings}) async {
    _settings = settings;
    await initialize(settings.recognitionLanguage);
    if (!await _recorder.hasPermission()) {
      _setState(SpeechRecognitionState.error);
      throw const PermissionException('需要麦克风权限才能使用语音输入。');
    }
    await cancelListening();
    _samples.clear();
    _result = null;
    _speechSeen = false;
    _stopping = false;
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _setState(SpeechRecognitionState.listening);
    _recording = stream.listen(_acceptAudio, onError: _onRecordingError);
  }

  void _acceptAudio(Uint8List bytes) {
    final samples = Float32List(bytes.length ~/ 2);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    _samples.addAll(samples);
    _vad?.acceptWaveform(samples);
    if (_vad?.isDetected() ?? false) {
      _speechSeen = true;
      _setState(SpeechRecognitionState.speechDetected);
    }
    if (_settings.inputMode == SpeechInputMode.vadAutoStop &&
        _speechSeen &&
        !(_vad?.isEmpty() ?? true) &&
        !_stopping) {
      _stopping = true;
      unawaited(stopListening());
    }
    if (_samples.length >= 16000 * _settings.maxRecordingSeconds &&
        !_stopping) {
      _stopping = true;
      unawaited(stopListening());
    }
  }

  void _onRecordingError(Object error, StackTrace stackTrace) {
    debugPrint('voice recording failed: $error');
    _setState(SpeechRecognitionState.error);
  }

  @override
  Future<SpeechRecognitionResult?> stopListening() async {
    if (_state != SpeechRecognitionState.listening &&
        _state != SpeechRecognitionState.speechDetected) {
      return _result;
    }
    await _recording?.cancel();
    _recording = null;
    await _recorder.stop();
    _setState(SpeechRecognitionState.processing);
    if (_samples.isEmpty) {
      _setState(SpeechRecognitionState.error);
      throw StateError('没有检测到语音。');
    }
    final stream = _recognizer!.createStream();
    try {
      stream.acceptWaveform(
        samples: Float32List.fromList(_samples),
        sampleRate: 16000,
      );
      _recognizer!.decode(stream);
      final decoded = _recognizer!.getResult(stream);
      _result = SpeechRecognitionResult(
        finalText: decoded.text.trim(),
        detectedLanguage: decoded.lang,
      );
    } finally {
      stream.free();
    }
    if (_result!.finalText.isEmpty) {
      _setState(SpeechRecognitionState.error);
      throw StateError('没有识别到可用文字。');
    }
    _partialController.add(_result!.finalText);
    _setState(SpeechRecognitionState.completed);
    return _result;
  }

  @override
  Future<void> cancelListening() async {
    await _recording?.cancel();
    _recording = null;
    await _recorder.stop();
    _vad?.reset();
    _samples.clear();
    _setState(SpeechRecognitionState.idle);
  }

  @override
  Future<void> pauseListening() => _recorder.pause();

  @override
  Future<void> resumeListening() => _recorder.resume();

  @override
  Future<void> dispose() async {
    await cancelListening();
    await _recorder.dispose();
    _recognizer?.free();
    _vad?.free();
    await _stateController.close();
    await _partialController.close();
  }
}

class PermissionException implements Exception {
  const PermissionException(this.message);
  final String message;

  @override
  String toString() => message;
}
