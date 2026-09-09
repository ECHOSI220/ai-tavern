import 'dart:typed_data';

enum SpeechRecognitionState {
  idle,
  loading,
  listening,
  speechDetected,
  processing,
  completed,
  error,
}

enum VoiceSessionState {
  idle,
  userInitializing,
  userListening,
  userSpeechDetected,
  userProcessing,
  aiGenerating,
  aiSpeaking,
  paused,
  error,
}

class SpeechRecognitionResult {
  const SpeechRecognitionResult({
    required this.finalText,
    this.partialText = '',
    this.detectedLanguage = '',
    this.confidence,
  });

  final String partialText;
  final String finalText;
  final String detectedLanguage;
  final double? confidence;
}

class VoiceSegment {
  const VoiceSegment({
    required this.text,
    this.type = VoiceSegmentType.dialogue,
    this.speaker,
  });

  final String text;
  final VoiceSegmentType type;
  final String? speaker;
}

enum VoiceSegmentType { dialogue, narration, system }

class SynthesizedAudio {
  const SynthesizedAudio({required this.samples, required this.sampleRate});

  final Float32List samples;
  final int sampleRate;
}

class VoiceModelMissingException implements Exception {
  const VoiceModelMissingException(this.message);
  final String message;

  @override
  String toString() => message;
}
