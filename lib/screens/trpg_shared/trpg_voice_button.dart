import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/voice_settings.dart';
import '../../repositories/settings_repository.dart';
import '../../services/voice/sherpa_speech_recognition_service.dart';
import '../../services/voice/speech_text_utils.dart';
import '../../services/voice/voice_model_manager.dart';
import '../../services/voice/voice_types.dart';
import '../app_settings/voice_settings_screen.dart';

/// Dictation only: never submits an action or locks a multiplayer turn.
class TrpgVoiceButton extends StatefulWidget {
  const TrpgVoiceButton({
    super.key,
    required this.controller,
    required this.settingsRepository,
    this.enabled = true,
    this.onStart,
  });
  final TextEditingController controller;
  final SettingsRepository settingsRepository;
  final bool enabled;
  final Future<void> Function()? onStart;
  @override
  State<TrpgVoiceButton> createState() => _TrpgVoiceButtonState();
}

class _TrpgVoiceButtonState extends State<TrpgVoiceButton>
    with WidgetsBindingObserver {
  SherpaSpeechRecognitionService? _service;
  StreamSubscription<SpeechRecognitionState>? _states;
  StreamSubscription<String>? _text;
  SpeechRecognitionState _state = SpeechRecognitionState.idle;
  VoiceSettings? _settings;
  bool _busy = false;
  bool _acceptText = false;
  bool get _listening =>
      _state == SpeechRecognitionState.listening ||
      _state == SpeechRecognitionState.speechDetected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _cancel() {
    _acceptText = false;
    unawaited(_service?.cancelListening());
  }

  @override
  void didUpdateWidget(covariant TrpgVoiceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _acceptText = false;
    unawaited(_states?.cancel());
    unawaited(_text?.cancel());
    unawaited(_service?.dispose());
    super.dispose();
  }

  Future<void> _openSettings() async {
    final settings = await widget.settingsRepository.load();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => VoiceSettingsScreen(
          initialSettings: settings,
          settingsRepository: widget.settingsRepository,
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      if (_listening) {
        await _service?.stopListening();
        return;
      }
      final settings = await widget.settingsRepository.load();
      if (!mounted || !widget.enabled) return;
      _settings = settings.voiceSettings;
      if (!_settings!.speechInputEnabled) {
        throw const VoiceModelMissingException('请先在语音设置中开启语音输入并下载识别模型');
      }
      if (_service == null) {
        _service = SherpaSpeechRecognitionService(VoiceModelManager());
        _states = _service!.states.listen((state) {
          if (mounted) setState(() => _state = state);
        });
        _text = _service!.partialText.listen((text) {
          if (!mounted ||
              !_acceptText ||
              !widget.enabled ||
              text.trim().isEmpty)
            return;
          _acceptText = false;
          final merged = mergeRecognizedText(
            existing: widget.controller.text,
            recognized: text,
            mode: _settings!.insertMode,
          );
          widget.controller.value = TextEditingValue(
            text: merged,
            selection: TextSelection.collapsed(offset: merged.length),
          );
        });
      }
      await widget.onStart?.call();
      if (!mounted || !widget.enabled) return;
      _acceptText = true;
      await _service!.startListening(settings: _settings!);
      if (!mounted || !widget.enabled) _cancel();
    } catch (error) {
      _acceptText = false;
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('语音输入失败：$error'),
            action: SnackBarAction(label: '语音设置', onPressed: _openSettings),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting =
        _busy ||
        _state == SpeechRecognitionState.processing ||
        _state == SpeechRecognitionState.loading;
    return IconButton(
      key: const ValueKey('trpg-voice-input'),
      tooltip: _listening ? '结束录音并转为文字' : '语音输入',
      onPressed: widget.enabled && !waiting ? _toggle : null,
      color: _listening ? Theme.of(context).colorScheme.error : null,
      icon: waiting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(_listening ? Icons.stop_circle_outlined : Icons.mic_none),
    );
  }
}
