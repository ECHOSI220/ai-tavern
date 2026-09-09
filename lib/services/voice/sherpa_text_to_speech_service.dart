import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../models/voice_settings.dart';
import 'speech_text_utils.dart';
import 'voice_model_manager.dart';
import 'voice_types.dart';

enum TextToSpeechState { idle, generating, playing, paused, error }

abstract interface class TextToSpeechService {
  TextToSpeechState get state;
  String? get speakingMessageId;
  Stream<TextToSpeechState> get states;
  Future<void> initialize();
  Future<void> speak(
    String text, {
    required CharacterVoiceConfig voice,
    String? messageId,
    bool speakNarration,
  });
  Future<void> stop();
  Future<void> pause();
  Future<void> resume();
  Future<void> dispose();
}

class SherpaTextToSpeechService implements TextToSpeechService {
  SherpaTextToSpeechService(this._models);

  final VoiceModelManager _models;
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _systemTts = FlutterTts();
  final _stateController = StreamController<TextToSpeechState>.broadcast();
  final _queue = <_SpeechJob>[];
  TextToSpeechState _state = TextToSpeechState.idle;
  bool _cancelled = false;
  bool _processing = false;
  String? _speakingMessageId;
  final _paths = <String, _TtsPaths>{};
  Completer<void>? _activePlayback;
  bool _systemInitialized = false;

  @override
  TextToSpeechState get state => _state;

  @override
  String? get speakingMessageId => _speakingMessageId;

  @override
  Stream<TextToSpeechState> get states => _stateController.stream;

  void _setState(TextToSpeechState value) {
    _state = value;
    _stateController.add(value);
  }

  @override
  Future<void> initialize() async {
    if (!_systemInitialized) {
      await _systemTts.awaitSpeakCompletion(true);
      await _systemTts.setLanguage('zh-CN');
      _systemInitialized = true;
    }
  }

  Future<_TtsPaths> _initializeProvider(String provider) async {
    final existing = _paths[provider];
    if (existing != null) return existing;
    final model = VoiceModelManager.kokoro;
    final status = await _models.status(model);
    if (!status.installed) {
      throw VoiceModelMissingException('尚未安装 ${model.name}。');
    }
    final dir = await _models.modelDirectory(model);
    String required(String name) {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && p.basename(entity.path) == name) {
          return entity.path;
        }
      }
      throw VoiceModelMissingException('${model.name} 缺少 $name。');
    }

    String optional(String name) {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && p.basename(entity.path) == name) {
          return entity.path;
        }
      }
      return '';
    }

    Directory? dataDir;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is Directory && p.basename(entity.path) == 'espeak-ng-data') {
        dataDir = entity;
        break;
      }
    }
    final paths = _TtsPaths(
      provider: provider,
      model: required('model.int8.onnx'),
      voices: required('voices.bin'),
      tokens: required('tokens.txt'),
      dataDir: dataDir?.path ?? '',
      lexicon: [
        optional('lexicon-zh.txt'),
        optional('lexicon-us-en.txt'),
      ].where((path) => path.isNotEmpty).join(','),
      ruleFsts: [
        optional('phone-zh.fst'),
        optional('date-zh.fst'),
        optional('number-zh.fst'),
      ].where((path) => path.isNotEmpty).join(','),
    );
    _paths[provider] = paths;
    return paths;
  }

  @override
  Future<void> speak(
    String text, {
    required CharacterVoiceConfig voice,
    String? messageId,
    bool speakNarration = true,
  }) async {
    final clean = sanitizeForSpeech(text, speakNarration: speakNarration);
    if (clean.isEmpty || !voice.enabled) return;
    await stop();
    if (voice.provider == 'system_mandarin') {
      await _speakSystemMandarin(clean, voice, messageId);
      return;
    }
    final paths = await _initializeProvider(voice.provider);
    _cancelled = false;
    _speakingMessageId = messageId;
    for (final sentence in splitSpeechSentences(clean)) {
      _queue.add(_SpeechJob(text: sentence, voice: voice));
    }
    await _drain(paths);
  }

  Future<void> _speakSystemMandarin(
    String text,
    CharacterVoiceConfig voice,
    String? messageId,
  ) async {
    if (!_systemInitialized) {
      await _systemTts.awaitSpeakCompletion(true);
      await _systemTts.setLanguage('zh-CN');
      final voices = await _systemTts.getVoices;
      if (voices is List) {
        final candidates = voices.whereType<Map>().where((item) {
          final locale = (item['locale'] ?? '').toString().toLowerCase();
          final network = item['network_required'];
          return locale.startsWith('zh-cn') && network != true;
        }).toList();
        if (candidates.isNotEmpty) {
          final chosen = candidates.first;
          await _systemTts.setVoice({
            'name': chosen['name'].toString(),
            'locale': chosen['locale'].toString(),
          });
        }
      }
      _systemInitialized = true;
    }
    _cancelled = false;
    _speakingMessageId = messageId;
    try {
      for (final sentence in splitSpeechSentences(text)) {
        if (_cancelled) break;
        _setState(TextToSpeechState.generating);
        await _systemTts.setSpeechRate((voice.speed * 0.5).clamp(0.25, 1));
        await _systemTts.setVolume(voice.volume);
        await _systemTts.setPitch(voice.pitch);
        _setState(TextToSpeechState.playing);
        await _systemTts.speak(sentence);
      }
      if (!_cancelled) _setState(TextToSpeechState.idle);
    } catch (_) {
      _setState(TextToSpeechState.error);
      rethrow;
    } finally {
      _speakingMessageId = null;
    }
  }

  Future<void> _drain(_TtsPaths paths) async {
    if (_processing) return;
    _processing = true;
    try {
      while (_queue.isNotEmpty && !_cancelled) {
        final job = _queue.removeAt(0);
        _setState(TextToSpeechState.generating);
        final temp = await getTemporaryDirectory();
        final file = File(
          p.join(
            temp.path,
            'ai_tavern_voice_${DateTime.now().microsecondsSinceEpoch}.wav',
          ),
        );
        final args = _TtsGenerateArgs(
          paths: paths,
          text: job.text,
          speakerId: int.tryParse(job.voice.voiceId) ?? 0,
          speed: job.voice.speed,
          outputPath: file.path,
        );
        await Isolate.run(() => _generateWav(args));
        if (_cancelled) {
          if (file.existsSync()) await file.delete();
          break;
        }
        _setState(TextToSpeechState.playing);
        final completed = Completer<void>();
        _activePlayback = completed;
        final subscription = _player.onPlayerComplete.listen((_) {
          if (!completed.isCompleted) completed.complete();
        });
        await _player.play(
          DeviceFileSource(file.path),
          volume: job.voice.volume,
        );
        await completed.future;
        _activePlayback = null;
        await subscription.cancel();
        if (file.existsSync()) await file.delete();
      }
      if (!_cancelled) _setState(TextToSpeechState.idle);
    } catch (_) {
      _setState(TextToSpeechState.error);
      rethrow;
    } finally {
      _queue.clear();
      _processing = false;
      _speakingMessageId = null;
    }
  }

  @override
  Future<void> stop() async {
    _cancelled = true;
    _queue.clear();
    await _systemTts.stop();
    await _player.stop();
    if (!(_activePlayback?.isCompleted ?? true)) {
      _activePlayback!.complete();
    }
    _activePlayback = null;
    _speakingMessageId = null;
    _setState(TextToSpeechState.idle);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    await _systemTts.pause();
    _setState(TextToSpeechState.paused);
  }

  @override
  Future<void> resume() async {
    await _player.resume();
    _setState(TextToSpeechState.playing);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _player.dispose();
    await _stateController.close();
  }
}

class _SpeechJob {
  const _SpeechJob({required this.text, required this.voice});
  final String text;
  final CharacterVoiceConfig voice;
}

class _TtsPaths {
  const _TtsPaths({
    required this.provider,
    required this.model,
    required this.voices,
    required this.tokens,
    required this.dataDir,
    required this.lexicon,
    required this.ruleFsts,
  });
  final String provider;
  final String model;
  final String voices;
  final String tokens;
  final String dataDir;
  final String lexicon;
  final String ruleFsts;
}

class _TtsGenerateArgs {
  const _TtsGenerateArgs({
    required this.paths,
    required this.text,
    required this.speakerId,
    required this.speed,
    required this.outputPath,
  });
  final _TtsPaths paths;
  final String text;
  final int speakerId;
  final double speed;
  final String outputPath;
}

void _generateWav(_TtsGenerateArgs args) {
  sherpa.initBindings();
  final tts = sherpa.OfflineTts(
    sherpa.OfflineTtsConfig(
      ruleFsts: args.paths.ruleFsts,
      model: sherpa.OfflineTtsModelConfig(
        kokoro: sherpa.OfflineTtsKokoroModelConfig(
          model: args.paths.model,
          voices: args.paths.voices,
          tokens: args.paths.tokens,
          dataDir: args.paths.dataDir,
          lexicon: args.paths.lexicon,
          lang: 'zh-en',
        ),
        numThreads: 2,
        debug: false,
      ),
    ),
  );
  try {
    final sid = args.speakerId.clamp(0, (tts.numSpeakers - 1).clamp(0, 10000));
    final audio = tts.generate(text: args.text, sid: sid, speed: args.speed);
    if (audio.samples.isEmpty) throw StateError('Kokoro 没有生成音频。');
    sherpa.writeWave(
      filename: args.outputPath,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
  } finally {
    tts.free();
  }
}
