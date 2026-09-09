import 'package:ai_tavern/models/app_settings.dart';
import 'package:ai_tavern/models/voice_settings.dart';
import 'package:ai_tavern/services/voice/speech_text_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('语音设置和角色独立 Voice 可以持久化', () {
    const voice = VoiceSettings(
      speechInputEnabled: true,
      recognitionLanguage: SpeechLanguageMode.auto,
      autoSend: true,
      insertMode: SpeechInsertMode.replace,
      ttsEnabled: true,
      autoSpeak: true,
      characterOverrides: {
        'rapi': CharacterVoiceConfig(
          voiceId: '3',
          speed: 1.2,
          volume: 0.8,
          autoSpeak: true,
        ),
      },
    );

    final restored = AppSettings.fromJson(
      const AppSettings(voiceSettings: voice).toJson(),
    ).voiceSettings;

    expect(restored.speechInputEnabled, isTrue);
    expect(restored.autoSend, isTrue);
    expect(restored.insertMode, SpeechInsertMode.replace);
    expect(restored.voiceFor('rapi').voiceId, '3');
    expect(restored.voiceFor('rapi').speed, 1.2);
    expect(restored.voiceFor('other').voiceId, '0');
    expect(restored.voiceFor('other').provider, 'system_mandarin');
  });

  test('旧版 Kokoro 默认配置升级后切换到轻量系统普通话', () {
    final restored = VoiceSettings.fromJson({
      'characterOverrides': {
        'legacy': {'provider': 'sherpa_kokoro', 'voiceId': '8'},
      },
    });

    expect(restored.defaultTtsProvider, 'system_mandarin');
    expect(restored.voiceFor('legacy').provider, 'system_mandarin');
    expect(restored.voiceFor('legacy').voiceId, '0');
  });

  test('识别结果追加时只在英文边界自动添加空格', () {
    expect(
      mergeRecognizedText(
        existing: 'Hello',
        recognized: 'Commander',
        mode: SpeechInsertMode.append,
      ),
      'Hello Commander',
    );
    expect(
      mergeRecognizedText(
        existing: '拉毗，',
        recognized: 'today 晚上吃什么？',
        mode: SpeechInsertMode.append,
      ),
      '拉毗，today 晚上吃什么？',
    );
    expect(
      mergeRecognizedText(
        existing: '旧文字',
        recognized: '新文字',
        mode: SpeechInsertMode.replace,
      ),
      '新文字',
    );
  });

  test('TTS 清理 Markdown、链接、代码、HTML 和 Emoji', () {
    final cleaned = sanitizeForSpeech(
      '# 标题\n**你好** [Commander](https://example.com) ❤️\n```dart\nprint(1);\n```\n<b>回来吧</b>',
    );

    expect(cleaned, contains('标题'));
    expect(cleaned, contains('你好 Commander'));
    expect(cleaned, contains('回来吧'));
    expect(cleaned, isNot(contains('https://')));
    expect(cleaned, isNot(contains('print(1)')));
    expect(cleaned, isNot(contains('❤️')));
  });

  test('关闭动作朗读时过滤括号动作', () {
    expect(
      sanitizeForSpeech('（拉毗轻轻叹气）“欢迎回来。”', speakNarration: false),
      '“欢迎回来。”',
    );
  });

  test('长文本按完整中英文句子切入朗读队列', () {
    expect(splitSpeechSentences('你好。Hello there! 今晚回来吗？最后一句'), [
      '你好。',
      'Hello there!',
      '今晚回来吗？',
      '最后一句',
    ]);
  });
}
