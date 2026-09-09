import '../models/api_profile.dart';
import '../models/app_settings.dart';
import '../models/chat_message.dart';
import '../models/player_reply_tone.dart';
import '../models/save_slot.dart';
import 'ai/ai_provider.dart';
import 'ai_service.dart';
import 'prompt_builder.dart';

class PlayerReplySuggestionService {
  const PlayerReplySuggestionService(this._aiService);

  final AiService _aiService;
  static const _promptBuilder = PromptBuilder();

  Future<String> generate({
    required ApiProfile profile,
    required String apiKey,
    required SaveSlot save,
    required List<ChatMessage> history,
    AppSettings settings = const AppSettings(),
    required PlayerReplyTone tone,
    String customTone = '',
    String draft = '',
  }) async {
    final requestedTone = customTone.trim().isEmpty
        ? '${tone.label}：${tone.instruction}'
        : '${tone.label}为基础，并额外遵循：${customTone.trim()}';
    final systemPrompt = _promptBuilder.buildSystemPrompt(
      save,
      history,
      settings: settings,
    );
    final playerName = save.playerName.trim().isEmpty ? '玩家' : save.playerName;
    final draftInstruction = draft.trim().isEmpty
        ? '当前没有草稿，请从零构思。'
        : '当前草稿如下，可保留合理部分并改写得更贴合情境：\n${draft.trim()}';
    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content':
            '''$systemPrompt

[临时任务：玩家回复建议]
你现在不是续写剧情的叙述者，而是帮助玩家构思下一句输入内容。
只从“$playerName”的立场写一段可直接输入的行动、对白或两者结合。
不要替任何 NPC 回答，不要描述后续结果，不要推进到对方回应之后。
不要输出分析、解释、标题、选项列表、Markdown、引号包裹或“建议：”前缀。
长度以一段 30—160 个汉字为宜，并严格服从玩家身份、已知信息和当前对话。''',
      },
      ...history
          .where(
            (message) =>
                message.errorMessage == null &&
                message.content.trim().isNotEmpty,
          )
          .map(
            (message) => {
              'role': message.role == ChatRole.user ? 'user' : 'assistant',
              'content': message.content,
            },
          ),
      {
        'role': 'user',
        'content': '请以“$requestedTone”的语气构思我下一步准备输入的内容。\n$draftInstruction',
      },
    ];

    final chunks = <String>[];
    await for (final chunk in _aiService.streamChat(
      profile: profile.copyWith(
        stream: false,
        temperature: 0.85,
        maxTokens: 500,
      ),
      apiKey: apiKey,
      messages: messages,
    )) {
      chunks.add(chunk);
    }
    final result = _clean(chunks.join());
    if (result.isEmpty) throw const AiException('AI 没有生成可用的回复建议');
    return result;
  }

  String _clean(String source) {
    var result = source.trim();
    result = result.replaceFirst(RegExp(r'^```(?:text|markdown)?\s*'), '');
    result = result.replaceFirst(RegExp(r'\s*```$'), '');
    result = result.replaceFirst(
      RegExp(r'^(?:玩家回复|回复建议|建议|玩家|台词)\s*[：:]\s*'),
      '',
    );
    final pairedQuotes = <(String, String)>[
      ('“', '”'),
      ('「', '」'),
      ('『', '』'),
      ('"', '"'),
    ];
    for (final pair in pairedQuotes) {
      if (result.startsWith(pair.$1) && result.endsWith(pair.$2)) {
        result = result.substring(
          pair.$1.length,
          result.length - pair.$2.length,
        );
        break;
      }
    }
    return result.trim();
  }
}
