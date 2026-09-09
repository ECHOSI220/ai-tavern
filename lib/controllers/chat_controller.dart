import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/api_profile.dart';
import '../models/app_settings.dart';
import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/memory_summary.dart';
import '../models/play_mode.dart';
import '../models/player_reply_tone.dart';
import '../models/save_slot.dart';
import '../repositories/api_repository.dart';
import '../repositories/save_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/ai/ai_provider.dart';
import '../services/ai_service.dart';
import '../services/conversation_memory_service.dart';
import '../services/context_compression_service.dart';
import '../services/choice_generation_service.dart';
import '../services/prompt_builder.dart';
import '../services/player_reply_suggestion_service.dart';
import '../services/vision/vision_context_formatter.dart';
import '../services/vision/vision_provider.dart';
import '../services/vision/vision_service.dart';

class ChatController extends ChangeNotifier {
  ChatController(
    this._saveRepository,
    this._apiRepository,
    this._settingsRepository,
    this._aiService, {
    required SaveSlot initialSave,
    VisionService? visionService,
  }) : _save = initialSave,
       _visionService = visionService ?? VisionService();

  final SaveRepository _saveRepository;
  final ApiRepository _apiRepository;
  final SettingsRepository _settingsRepository;
  final AiService _aiService;
  final VisionService _visionService;
  final VisionContextFormatter _visionContextFormatter =
      const VisionContextFormatter();
  final PromptBuilder _promptBuilder = const PromptBuilder();
  final ConversationMemoryService _conversationMemoryService =
      const ConversationMemoryService();
  final ContextCompressionService _contextCompressionService =
      const ContextCompressionService();
  final ChoiceGenerationService _choiceGenerationService =
      const ChoiceGenerationService();
  late final PlayerReplySuggestionService _playerReplySuggestionService =
      PlayerReplySuggestionService(_aiService);
  static const _uuid = Uuid();

  SaveSlot _save;
  AppSettings _settings = const AppSettings();
  List<ApiProfile> _profiles = const [];
  ApiProfile? _selectedProfile;
  bool _loading = true;
  bool _generating = false;
  bool _generatingChoices = false;
  bool _refiningChoices = false;
  bool _compressingContext = false;
  bool _generatingPlayerReply = false;
  bool _analyzingImages = false;
  String? _choiceError;
  String? _contextCompressionError;
  String? _visionError;
  bool _stopRequested = false;
  String? _activeAssistantId;
  DateTime _lastStreamingCheckpoint = DateTime.fromMillisecondsSinceEpoch(0);
  void Function(ChatMessage message)? onAssistantCompleted;

  SaveSlot get save => _save;
  AppSettings get settings => _settings;
  List<ApiProfile> get profiles => _profiles;
  ApiProfile? get selectedProfile => _selectedProfile;
  bool get loading => _loading;
  bool get generating => _generating;
  bool get generatingChoices => _generatingChoices;
  bool get refiningChoices => _refiningChoices;
  bool get compressingContext => _compressingContext;
  bool get generatingPlayerReply => _generatingPlayerReply;
  bool get analyzingImages => _analyzingImages;
  String? get choiceError => _choiceError;
  String? get contextCompressionError => _contextCompressionError;
  String? get visionError => _visionError;

  Future<void> initialize() async {
    await reload();
    _settings = await _settingsRepository.load();
    _profiles = await _apiRepository.getAll();
    _selectedProfile = _profiles.cast<ApiProfile?>().firstWhere(
      (profile) => profile?.id == _settings.defaultApiProfileId,
      orElse: () => _profiles.isEmpty ? null : _profiles.first,
    );
    if (_save.messages.isEmpty && _save.openingMessage.trim().isNotEmpty) {
      final now = DateTime.now();
      _save = _save.copyWith(
        messages: [
          ChatMessage(
            id: _uuid.v4(),
            saveId: _save.id,
            role: ChatRole.assistant,
            content: _save.openingMessage.trim(),
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      await _persist();
    } else if (_updateConversationMemory()) {
      await _persist(updateConversationMemory: false);
    }
    _loading = false;
    notifyListeners();
    await ensureChoices();
  }

  Future<void> reload() async {
    final complete = await _saveRepository.getById(_save.id);
    if (complete != null) _save = complete;
    notifyListeners();
  }

  void selectProfile(ApiProfile profile) {
    _selectedProfile = profile;
    notifyListeners();
  }

  Future<void> refreshProfiles() async {
    _settings = await _settingsRepository.load();
    _profiles = await _apiRepository.getAll();
    if (_selectedProfile == null ||
        !_profiles.any((item) => item.id == _selectedProfile!.id)) {
      _selectedProfile = _profiles.cast<ApiProfile?>().firstWhere(
        (profile) => profile?.id == _settings.defaultApiProfileId,
        orElse: () => _profiles.isEmpty ? null : _profiles.first,
      );
    }
    notifyListeners();
  }

  Future<void> sendUserMessage(
    String content, {
    List<ChatAttachment> attachments = const [],
  }) async {
    final text = content.trim();
    if ((text.isEmpty && attachments.isEmpty) ||
        _generating ||
        _analyzingImages ||
        _generatingChoices ||
        _compressingContext ||
        _generatingPlayerReply) {
      return;
    }
    final now = DateTime.now();
    final parent = _save.messages.isEmpty ? null : _save.messages.last.id;
    final userMessage = ChatMessage(
      id: _uuid.v4(),
      saveId: _save.id,
      role: ChatRole.user,
      content: text,
      attachments: attachments,
      createdAt: now,
      updatedAt: now,
      parentMessageId: parent,
    );
    _save = _save.copyWith(messages: [..._save.messages, userMessage]);
    await _persist();
    notifyListeners();
    if (attachments.isNotEmpty) {
      final ready = await _analyzeMessageImages(userMessage.id);
      if (!ready && text.isEmpty) return;
    }
    await _generateAssistant();
  }

  Future<bool> _analyzeMessageImages(String messageId) async {
    final original = _messageById(messageId);
    if (original == null || !original.hasImages) return true;
    final settings = _settings.visionSettings;
    _visionError = null;
    if (!settings.enabled ||
        settings.baseUrl.trim().isEmpty ||
        settings.model.trim().isEmpty) {
      const error = '看图能力尚未配置，请先在应用设置 → 看图能力中完成配置。';
      _visionError = error;
      _replaceMessage(
        original.copyWith(
          attachments: original.attachments
              .map(
                (item) => item.copyWith(
                  analysisStatus: AttachmentAnalysisStatus.error,
                  errorMessage: error,
                ),
              )
              .toList(),
        ),
      );
      await _persist();
      notifyListeners();
      return false;
    }

    _analyzingImages = true;
    _replaceMessage(
      original.copyWith(
        attachments: original.attachments
            .map(
              (item) => item.copyWith(
                analysisStatus: AttachmentAnalysisStatus.analyzing,
                clearError: true,
              ),
            )
            .toList(),
      ),
    );
    await _persist();
    notifyListeners();
    try {
      final apiKey = await _apiRepository.readVisionApiKey();
      final analyses = await _visionService.analyzeImages(
        settings: settings,
        apiKey: apiKey,
        images: original.attachments,
        userQuestion: original.content,
      );
      final completedAttachments = <ChatAttachment>[];
      for (var index = 0; index < original.attachments.length; index++) {
        completedAttachments.add(
          original.attachments[index].copyWith(
            analysisStatus: AttachmentAnalysisStatus.analyzed,
            analysis: analyses[index],
            clearError: true,
          ),
        );
      }
      _replaceMessage(
        original.copyWith(
          attachments: completedAttachments,
          visionContext: _visionContextFormatter.format(
            analyses,
            userText: original.content,
          ),
        ),
      );
      await _persist();
      return true;
    } catch (error) {
      final message = error is VisionException
          ? error.toString()
          : '图片分析失败：$error';
      _visionError = message;
      _replaceMessage(
        original.copyWith(
          attachments: original.attachments
              .map(
                (item) => item.copyWith(
                  analysisStatus: AttachmentAnalysisStatus.error,
                  errorMessage: message,
                ),
              )
              .toList(),
        ),
      );
      await _persist();
      return false;
    } finally {
      _analyzingImages = false;
      notifyListeners();
    }
  }

  Future<void> retryVision(String messageId) async {
    if (_generating || _analyzingImages || _compressingContext) return;
    final message = _messageById(messageId);
    if (message == null || !message.hasImages) return;
    final ready = await _analyzeMessageImages(messageId);
    final refreshedIndex = _save.messages.indexWhere(
      (item) => item.id == messageId,
    );
    if (ready && refreshedIndex == _save.messages.length - 1) {
      await _generateAssistant();
    }
  }

  Future<String> generatePlayerReply({
    required PlayerReplyTone tone,
    String customTone = '',
    String draft = '',
  }) async {
    if (_generating ||
        _generatingChoices ||
        _compressingContext ||
        _generatingPlayerReply) {
      throw const AiException('请等待当前 AI 任务结束');
    }
    final profile = _selectedProfile;
    if (profile == null) throw const AiException('尚未配置 AI API');

    _generatingPlayerReply = true;
    notifyListeners();
    try {
      final history = _historyEndingAt(_save.messages.length);
      final apiKey = await _apiRepository.readApiKey(profile.id);
      return await _playerReplySuggestionService.generate(
        profile: profile,
        apiKey: apiKey,
        save: _save,
        history: history,
        settings: _settings,
        tone: tone,
        customTone: customTone,
        draft: draft,
      );
    } finally {
      _generatingPlayerReply = false;
      notifyListeners();
    }
  }

  Future<void> selectChoice(String choice) async {
    final text = choice.trim();
    if (_save.playMode != PlayMode.choice ||
        !_save.pendingChoices.contains(choice) ||
        text.isEmpty ||
        _generating ||
        _generatingChoices ||
        _compressingContext) {
      return;
    }
    _choiceError = null;
    _save = _save.copyWith(pendingChoices: const []);
    await _persist();
    notifyListeners();
    await sendUserMessage(text);
  }

  Future<void> submitFreeChoice(
    String content, {
    List<ChatAttachment> attachments = const [],
  }) async {
    final text = content.trim();
    if (_save.playMode != PlayMode.choice ||
        (text.isEmpty && attachments.isEmpty) ||
        _generating ||
        _analyzingImages ||
        _generatingChoices ||
        _compressingContext ||
        _generatingPlayerReply) {
      return;
    }
    _choiceError = null;
    _save = _save.copyWith(pendingChoices: const []);
    await _persist();
    notifyListeners();
    await sendUserMessage(text, attachments: attachments);
  }

  Future<void> _generateAssistant() async {
    if (_generating) return;
    final profile = _selectedProfile;
    final now = DateTime.now();
    final assistant = ChatMessage(
      id: _uuid.v4(),
      saveId: _save.id,
      role: ChatRole.assistant,
      content: '',
      createdAt: now,
      updatedAt: now,
      parentMessageId: _save.messages.isEmpty ? null : _save.messages.last.id,
    );
    _save = _save.copyWith(messages: [..._save.messages, assistant]);
    _activeAssistantId = assistant.id;
    _generating = true;
    _stopRequested = false;
    notifyListeners();

    if (profile == null) {
      _replaceMessage(
        assistant.copyWith(errorMessage: '尚未配置 AI API，请先在设置中创建配置。'),
      );
      _generating = false;
      _activeAssistantId = null;
      await _persist();
      notifyListeners();
      await ensureChoices(force: true);
      return;
    }

    final history = _historyBefore(assistant.id);
    final systemPrompt = _promptBuilder.buildSystemPrompt(
      _save,
      history,
      settings: _settings,
    );
    final requestMessages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      ...history
          .where((message) => message.hasModelContent)
          .map(
            (message) => {
              'role': message.role == ChatRole.user ? 'user' : 'assistant',
              'content': message.modelContent,
            },
          ),
    ];

    var completed = false;
    try {
      final apiKey = await _apiRepository.readApiKey(profile.id);
      var content = '';
      await for (final chunk in _aiService.streamChat(
        profile: profile,
        apiKey: apiKey,
        messages: requestMessages,
      )) {
        content += chunk;
        _replaceMessage(
          assistant.copyWith(content: content, updatedAt: DateTime.now()),
        );
        notifyListeners();
        final checkpointAt = DateTime.now();
        if (checkpointAt.difference(_lastStreamingCheckpoint) >=
            const Duration(seconds: 2)) {
          // 流式生成时定期落盘；即使用户直接关闭窗口，也只会丢失极少量尾部文本。
          await _persist();
          _lastStreamingCheckpoint = checkpointAt;
        }
      }
      if (_stopRequested) {
        final current = _messageById(assistant.id);
        if (current != null) {
          _replaceMessage(current.copyWith(isInterrupted: true));
        }
      } else {
        completed = content.trim().isNotEmpty;
      }
    } on AiException catch (error) {
      final current = _messageById(assistant.id) ?? assistant;
      _replaceMessage(current.copyWith(errorMessage: error.toString()));
    } catch (error) {
      final current = _messageById(assistant.id) ?? assistant;
      _replaceMessage(current.copyWith(errorMessage: '生成失败：$error'));
    } finally {
      _generating = false;
      _activeAssistantId = null;
      await _persist();
      notifyListeners();
    }
    if (completed) {
      final finished = _messageById(assistant.id);
      if (finished != null) onAssistantCompleted?.call(finished);
      await _maybeCompressContext();
      await ensureChoices(force: true);
    }
  }

  Future<void> ensureChoices({bool force = false}) async {
    if (_save.playMode != PlayMode.choice ||
        _generating ||
        _compressingContext ||
        _generatingChoices ||
        (!force && _save.pendingChoices.isNotEmpty) ||
        !_canOfferChoices()) {
      return;
    }
    _generatingChoices = true;
    _choiceError = null;
    if (force) _save = _save.copyWith(pendingChoices: const []);
    notifyListeners();

    final profile = _selectedProfile;
    if (profile == null) {
      await _useFallbackChoices('尚未配置 AI API，当前显示本地备用选项。');
      return;
    }

    try {
      final history = _choiceHistory();
      final systemPrompt = _promptBuilder.buildSystemPrompt(
        _save,
        history,
        settings: _settings,
      );
      final apiKey = await _apiRepository.readApiKey(profile.id);
      final chunks = <String>[];
      await for (final chunk in _aiService.streamChat(
        profile: profile.copyWith(
          stream: false,
          maxTokens: (_save.choiceCount * 120).clamp(400, 1200),
        ),
        apiKey: apiKey,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          ...history.map(
            (message) => {
              'role': message.role == ChatRole.user ? 'user' : 'assistant',
              'content': message.modelContent,
            },
          ),
          {
            'role': 'user',
            'content': _choiceGenerationService.instruction(_save.choiceCount),
          },
        ],
      )) {
        chunks.add(chunk);
      }
      final choices = _choiceGenerationService.parseAndFill(
        chunks.join(),
        _save.choiceCount,
      );
      _save = _save.copyWith(pendingChoices: choices);
      _generatingChoices = false;
      await _persist();
      notifyListeners();
    } catch (error) {
      await _useFallbackChoices('选项生成失败，当前显示本地备用选项：$error');
    }
  }

  Future<void> regenerateChoices() => ensureChoices(force: true);

  Future<void> refineChoices() async {
    if (_save.playMode != PlayMode.choice ||
        _save.pendingChoices.isEmpty ||
        _generating ||
        _compressingContext ||
        _generatingChoices ||
        !_canOfferChoices()) {
      return;
    }
    final profile = _selectedProfile;
    if (profile == null) {
      _choiceError = '尚未配置 AI API，无法细化选项。';
      notifyListeners();
      return;
    }

    final originalChoices = [..._save.pendingChoices];
    _generatingChoices = true;
    _refiningChoices = true;
    _choiceError = null;
    notifyListeners();
    try {
      final history = _choiceHistory();
      final systemPrompt = _promptBuilder.buildSystemPrompt(
        _save,
        history,
        settings: _settings,
      );
      final apiKey = await _apiRepository.readApiKey(profile.id);
      final chunks = <String>[];
      await for (final chunk in _aiService.streamChat(
        profile: profile.copyWith(
          stream: false,
          maxTokens: (_save.choiceCount * 180).clamp(600, 1800),
        ),
        apiKey: apiKey,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          ...history.map(
            (message) => {
              'role': message.role == ChatRole.user ? 'user' : 'assistant',
              'content': message.modelContent,
            },
          ),
          {
            'role': 'user',
            'content': _choiceGenerationService.refinementInstruction(
              currentChoices: originalChoices,
              count: _save.choiceCount,
              playerName: _save.playerName,
            ),
          },
        ],
      )) {
        chunks.add(chunk);
      }
      final refined = _choiceGenerationService.parseAndFill(
        chunks.join(),
        _save.choiceCount,
        fallbackChoices: _choiceGenerationService.refinementFallback(
          currentChoices: originalChoices,
          count: _save.choiceCount,
          playerName: _save.playerName,
        ),
      );
      _save = _save.copyWith(pendingChoices: refined);
      await _persist();
    } catch (error) {
      _save = _save.copyWith(pendingChoices: originalChoices);
      _choiceError = '选项细化失败，已保留原选项：$error';
    } finally {
      _generatingChoices = false;
      _refiningChoices = false;
      notifyListeners();
    }
  }

  bool _canOfferChoices() {
    for (final message in _save.messages.reversed) {
      if (message.errorMessage != null || !message.hasModelContent) {
        continue;
      }
      return message.role == ChatRole.assistant;
    }
    return false;
  }

  List<ChatMessage> _choiceHistory() => _historyEndingAt(_save.messages.length);

  List<ChatMessage> _historyEndingAt(int end) {
    var start = 0;
    if (_settings.autoContextCompression &&
        _save.memorySummary.content.trim().isNotEmpty &&
        _save.memorySummary.coveredMessageId != null) {
      final coveredIndex = _save.messages.indexWhere(
        (message) => message.id == _save.memorySummary.coveredMessageId,
      );
      if (coveredIndex >= 0) start = (coveredIndex + 1).clamp(0, end);
    }
    final valid = _save.messages
        .skip(start)
        .take(end - start)
        .where(
          (message) =>
              message.role != ChatRole.system &&
              message.errorMessage == null &&
              message.hasModelContent,
        )
        .toList();
    final limit = _settings.historyMessageCount;
    return valid.length <= limit ? valid : valid.sublist(valid.length - limit);
  }

  Future<void> _useFallbackChoices(String message) async {
    _choiceError = message;
    _save = _save.copyWith(
      pendingChoices: _choiceGenerationService.fallback(_save.choiceCount),
    );
    _generatingChoices = false;
    await _persist();
    notifyListeners();
  }

  List<ChatMessage> _historyBefore(String messageId) {
    final index = _save.messages.indexWhere((item) => item.id == messageId);
    final end = index < 0 ? _save.messages.length : index;
    return _historyEndingAt(end);
  }

  Future<void> stopGeneration() async {
    if (!_generating && !_analyzingImages) return;
    if (_analyzingImages) {
      _visionService.cancel();
      _analyzingImages = false;
    }
    if (!_generating) {
      notifyListeners();
      return;
    }
    _stopRequested = true;
    _aiService.cancel();
    final id = _activeAssistantId;
    if (id != null) {
      final current = _messageById(id);
      if (current != null) {
        _replaceMessage(current.copyWith(isInterrupted: true));
        await _persist();
      }
    }
    notifyListeners();
  }

  Future<void> editMessage(String id, String content) async {
    final current = _messageById(id);
    if (current == null) return;
    _replaceMessage(
      ChatMessage(
        id: current.id,
        saveId: current.saveId,
        role: current.role,
        content: content.trim(),
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
        branchId: current.branchId,
        parentMessageId: current.parentMessageId,
        generationIndex: current.generationIndex,
        isInterrupted: false,
        attachments: current.attachments,
        visionContext: current.visionContext,
      ),
    );
    _save = _save.copyWith(pendingChoices: const []);
    await _persist();
    notifyListeners();
    await ensureChoices();
  }

  Future<void> deleteMessage(String id) async {
    _save = _save.copyWith(
      messages: _save.messages.where((message) => message.id != id).toList(),
      pendingChoices: const [],
    );
    await _persist(replaceMessages: true);
    notifyListeners();
    await ensureChoices();
  }

  Future<void> continueFrom(String id) async {
    final index = _save.messages.indexWhere((message) => message.id == id);
    if (index < 0) return;
    _save = _save.copyWith(
      messages: _save.messages.sublist(0, index + 1),
      pendingChoices: const [],
    );
    await _persist(replaceMessages: true);
    notifyListeners();
    await ensureChoices();
  }

  Future<void> regenerate(String assistantId) async {
    if (_generating) return;
    final index = _save.messages.indexWhere(
      (message) => message.id == assistantId,
    );
    if (index < 0 || _save.messages[index].role != ChatRole.assistant) return;
    _save = _save.copyWith(
      messages: _save.messages.sublist(0, index),
      pendingChoices: const [],
    );
    await _persist(replaceMessages: true);
    notifyListeners();
    await _generateAssistant();
  }

  Future<String> generateMemorySummary() async {
    if (_generating) throw const AiException('请先等待当前生成结束');
    if (_compressingContext) throw const AiException('上下文正在压缩');
    final summary = await _compressContext(force: true, throwOnError: true);
    return summary ?? _save.memorySummary.content;
  }

  Future<void> _maybeCompressContext() async {
    if (!_settings.autoContextCompression) return;
    await _compressContext(force: false, throwOnError: false);
  }

  Future<String?> _compressContext({
    required bool force,
    required bool throwOnError,
  }) async {
    final profile = _selectedProfile;
    if (profile == null) {
      if (throwOnError) throw const AiException('尚未配置 AI API');
      return null;
    }
    if (_compressingContext) return null;

    final valid = _contextCompressionService.validMessages(_save.messages);
    if (valid.isEmpty) {
      if (throwOnError) throw const AiException('暂无可压缩的对话记录');
      return null;
    }
    var pending = _contextCompressionService.pendingMessages(_save);
    if (!force &&
        pending.length < _settings.contextCompressionInterval.clamp(2, 30)) {
      return null;
    }
    if (force && pending.isEmpty) pending = valid;

    _compressingContext = true;
    _contextCompressionError = null;
    notifyListeners();
    try {
      final apiKey = await _apiRepository.readApiKey(profile.id);
      final summaryProfile = profile.copyWith(
        stream: false,
        temperature: 0.2,
        maxTokens: 1600,
      );
      final chunks = <String>[];
      await for (final chunk in _aiService.streamChat(
        profile: summaryProfile,
        apiKey: apiKey,
        messages: _contextCompressionService.buildRequest(_save, pending),
      )) {
        chunks.add(chunk);
      }
      final summary = chunks.join().trim();
      if (summary.isEmpty) throw const AiException('压缩结果为空');
      final now = DateTime.now();
      _save = _save.copyWith(
        memorySummary: MemorySummary(
          content: summary,
          updatedAt: now,
          coveredMessageId: valid.last.id,
        ),
        updatedAt: now,
      );
      _updateConversationMemory();
      await _persist(updateConversationMemory: false);
      return summary;
    } catch (error) {
      _contextCompressionError = '上下文压缩失败：$error';
      if (throwOnError) rethrow;
      return null;
    } finally {
      _compressingContext = false;
      notifyListeners();
    }
  }

  ChatMessage? _messageById(String id) {
    for (final message in _save.messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  void _replaceMessage(ChatMessage message) {
    final list = [..._save.messages];
    final index = list.indexWhere((item) => item.id == message.id);
    if (index >= 0) {
      list[index] = message;
      _save = _save.copyWith(messages: list);
    }
  }

  bool _updateConversationMemory() {
    var messages = _save.messages;
    if (_settings.autoContextCompression &&
        _save.memorySummary.content.trim().isNotEmpty &&
        _save.memorySummary.coveredMessageId != null) {
      final coveredIndex = messages.indexWhere(
        (message) => message.id == _save.memorySummary.coveredMessageId,
      );
      if (coveredIndex >= 0) messages = messages.sublist(coveredIndex + 1);
    }
    final value = _conversationMemoryService.build(
      messages,
      playerName: _save.playerName,
    );
    if (value == _save.conversationMemory) return false;
    _save = _save.copyWith(conversationMemory: value);
    return true;
  }

  Future<void> _persist({
    bool updateConversationMemory = true,
    bool replaceMessages = false,
  }) async {
    final now = DateTime.now();
    if (updateConversationMemory) _updateConversationMemory();
    _save = _save.copyWith(updatedAt: now, lastPlayedAt: now);
    await _saveRepository.upsert(_save, replaceMessages: replaceMessages);
  }

  @override
  void dispose() {
    _aiService.cancel();
    _visionService.cancel();
    super.dispose();
  }
}
