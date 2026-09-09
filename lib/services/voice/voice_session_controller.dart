import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/voice_settings.dart';
import 'sherpa_speech_recognition_service.dart';
import 'sherpa_text_to_speech_service.dart';
import 'voice_types.dart';

class VoiceSessionController extends ChangeNotifier {
  VoiceSessionController({required this.recognition, required this.speech}) {
    _recognitionSubscription = recognition.states.listen((state) {
      _state = switch (state) {
        SpeechRecognitionState.loading => VoiceSessionState.userInitializing,
        SpeechRecognitionState.listening => VoiceSessionState.userListening,
        SpeechRecognitionState.speechDetected =>
          VoiceSessionState.userSpeechDetected,
        SpeechRecognitionState.processing => VoiceSessionState.userProcessing,
        SpeechRecognitionState.completed ||
        SpeechRecognitionState.idle => VoiceSessionState.idle,
        SpeechRecognitionState.error => VoiceSessionState.error,
      };
      notifyListeners();
    });
    _speechSubscription = speech.states.listen((state) {
      _state = switch (state) {
        TextToSpeechState.generating ||
        TextToSpeechState.playing => VoiceSessionState.aiSpeaking,
        TextToSpeechState.paused => VoiceSessionState.paused,
        TextToSpeechState.error => VoiceSessionState.error,
        TextToSpeechState.idle => VoiceSessionState.idle,
      };
      notifyListeners();
    });
  }

  final SpeechRecognitionService recognition;
  final TextToSpeechService speech;
  StreamSubscription<SpeechRecognitionState>? _recognitionSubscription;
  StreamSubscription<TextToSpeechState>? _speechSubscription;
  VoiceSessionState _state = VoiceSessionState.idle;

  VoiceSessionState get state => _state;
  SpeechRecognitionState get recognitionState => recognition.state;
  TextToSpeechState get speechState => speech.state;
  String? get speakingMessageId => speech.speakingMessageId;

  Future<void> startListening(VoiceSettings settings) async {
    // User barge-in always wins: stop playback and clear queued speech first.
    await speech.stop();
    await recognition.startListening(settings: settings);
  }

  Future<SpeechRecognitionResult?> stopListening() =>
      recognition.stopListening();

  Future<void> cancelListening() => recognition.cancelListening();

  Future<void> speak(
    String text, {
    required CharacterVoiceConfig voice,
    required bool speakNarration,
    String? messageId,
  }) async {
    await recognition.cancelListening();
    await speech.speak(
      text,
      voice: voice,
      speakNarration: speakNarration,
      messageId: messageId,
    );
  }

  Future<void> stopSpeaking() => speech.stop();
  Future<void> pauseSpeaking() => speech.pause();
  Future<void> resumeSpeaking() => speech.resume();

  @override
  void dispose() {
    unawaited(_recognitionSubscription?.cancel());
    unawaited(_speechSubscription?.cancel());
    unawaited(recognition.dispose());
    unawaited(speech.dispose());
    super.dispose();
  }
}
