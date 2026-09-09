import '../../app/skins/skin_icon.dart';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../app/skins/theme_background.dart';
import '../app_settings/skin_gallery_page.dart';
import 'package:flutter/services.dart';

import '../../controllers/chat_controller.dart';
import '../../models/api_profile.dart';
import '../../models/chat_attachment.dart';
import '../../models/chat_message.dart';
import '../../models/play_mode.dart';
import '../../models/player_reply_tone.dart';
import '../../models/save_slot.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../repositories/save_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/vision/image_preprocessor.dart';
import '../../services/voice/sherpa_speech_recognition_service.dart';
import '../../services/voice/sherpa_text_to_speech_service.dart';
import '../../services/voice/speech_text_utils.dart';
import '../../services/voice/voice_model_manager.dart';
import '../../services/voice/voice_session_controller.dart';
import '../../services/voice/voice_types.dart';
import '../../widgets/collapsible_choice_panel.dart';
import '../../widgets/message_bubble.dart';
import '../api_settings/api_settings_screen.dart';
import '../character_editor/character_list_screen.dart';
import '../lorebook/lorebook_screen.dart';
import '../memory/memory_screen.dart';
import '../save_editor/save_editor_screen.dart';
import 'prompt_preview_screen.dart';
import 'player_reply_tone_dialog.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.save,
    required this.saveRepository,
    required this.characterCardRepository,
    required this.apiRepository,
    required this.settingsRepository,
    required this.aiService,
    super.key,
  });

  final SaveSlot save;
  final SaveRepository saveRepository;
  final CharacterCardRepository characterCardRepository;
  final ApiRepository apiRepository;
  final SettingsRepository settingsRepository;
  final AiService aiService;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late final ChatController _controller;
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  late final VoiceModelManager _voiceModels;
  late final VoiceSessionController _voice;
  StreamSubscription<String>? _speechTextSubscription;
  PlayerReplyTone _replyTone = PlayerReplyTone.natural;
  final _imagePreprocessor = const ImagePreprocessor();
  List<ChatAttachment> _pendingImages = const [];
  var _pickingImages = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller =
        ChatController(
            widget.saveRepository,
            widget.apiRepository,
            widget.settingsRepository,
            widget.aiService,
            initialSave: widget.save,
          )
          ..addListener(_onControllerChanged)
          ..onAssistantCompleted = _autoSpeakAssistant;
    _voiceModels = VoiceModelManager();
    _voice = VoiceSessionController(
      recognition: SherpaSpeechRecognitionService(_voiceModels),
      speech: SherpaTextToSpeechService(_voiceModels),
    )..addListener(_onVoiceChanged);
    _speechTextSubscription = _voice.recognition.partialText.listen((text) {
      if (text.trim().isNotEmpty) unawaited(_applySpeechResult(text));
    });
    _controller.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_voice.cancelListening());
      unawaited(_voice.stopSpeaking());
    }
  }

  void _onVoiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _autoSpeakAssistant(ChatMessage message) async {
    final voiceSettings = _controller.settings.voiceSettings;
    final characterId = _controller.save.characters
        .where((item) => item.enabled)
        .firstOrNull
        ?.id;
    final characterVoice = voiceSettings.voiceFor(characterId);
    if (!voiceSettings.ttsEnabled || !characterVoice.autoSpeak) return;
    await _speakMessage(message);
  }

  Future<void> _speakMessage(ChatMessage message) async {
    final settings = _controller.settings.voiceSettings;
    if (!settings.ttsEnabled) {
      _voiceError('请先在应用设置 → 语音中启用 AI 文字朗读。');
      return;
    }
    if (_voice.speakingMessageId == message.id) {
      await _voice.stopSpeaking();
      return;
    }
    final characterId = _controller.save.characters
        .where((item) => item.enabled)
        .firstOrNull
        ?.id;
    try {
      await _voice.speak(
        message.content,
        voice: settings.voiceFor(characterId),
        speakNarration: settings.speakNarration,
        messageId: message.id,
      );
    } catch (error) {
      _voiceError('朗读失败：$error');
    }
  }

  Future<void> _toggleMicrophone() async {
    final settings = _controller.settings.voiceSettings;
    if (!settings.speechInputEnabled) {
      _voiceError('请先在应用设置 → 语音中启用语音输入。');
      return;
    }
    if (_voice.state == VoiceSessionState.userInitializing ||
        _voice.state == VoiceSessionState.userProcessing) {
      return;
    }
    try {
      if (_voice.state == VoiceSessionState.userListening ||
          _voice.state == VoiceSessionState.userSpeechDetected) {
        await _voice.stopListening();
      } else {
        await _voice.startListening(settings);
      }
    } catch (error) {
      _voiceError('语音输入失败：$error');
      // 让按钮从错误状态回到普通状态，用户可再次点击重试。
      try {
        await _voice.cancelListening();
      } catch (_) {}
    }
  }

  Future<void> _applySpeechResult(String recognized) async {
    final settings = _controller.settings.voiceSettings;
    final merged = mergeRecognizedText(
      existing: _input.text,
      recognized: recognized,
      mode: settings.insertMode,
    );
    _input.value = TextEditingValue(
      text: merged,
      selection: TextSelection.collapsed(offset: merged.length),
    );
    if (settings.autoSend) {
      if (_controller.save.playMode == PlayMode.choice) {
        await _submitFreeChoice();
      } else {
        await _send();
      }
    }
  }

  void _voiceError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _micTooltip() {
    switch (_voice.state) {
      case VoiceSessionState.userInitializing:
        return '正在初始化语音模型…';
      case VoiceSessionState.userListening:
        return '停止并识别';
      case VoiceSessionState.userSpeechDetected:
        return '正在听，点击停止并识别';
      case VoiceSessionState.userProcessing:
        return '正在识别…';
      case VoiceSessionState.error:
        return '语音输入失败，点击重试';
      default:
        return '语音输入';
    }
  }

  Color? _micColor(ColorScheme colors) {
    switch (_voice.state) {
      case VoiceSessionState.userListening:
      case VoiceSessionState.userSpeechDetected:
      case VoiceSessionState.error:
        return colors.error;
      case VoiceSessionState.userInitializing:
      case VoiceSessionState.userProcessing:
        return colors.primary;
      default:
        return null;
    }
  }

  Widget _micIcon() {
    switch (_voice.state) {
      case VoiceSessionState.userInitializing:
      case VoiceSessionState.userProcessing:
        return const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case VoiceSessionState.userListening:
        return const SkinIcon(Icons.stop_circle);
      case VoiceSessionState.userSpeechDetected:
        return const SkinIcon(Icons.graphic_eq);
      case VoiceSessionState.error:
        return const SkinIcon(Icons.mic_off);
      default:
        return const SkinIcon(Icons.mic_none);
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.settings.autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _voice
      ..removeListener(_onVoiceChanged)
      ..dispose();
    unawaited(_speechTextSubscription?.cancel());
    _voiceModels.dispose();
    for (final image in _pendingImages) {
      final file = File(image.localPath);
      if (file.existsSync()) file.deleteSync();
    }
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _stopGenerationAndSpeech() async {
    await _voice.stopSpeaking();
    await _controller.stopGeneration();
  }

  Future<void> _send() async {
    final text = _input.text;
    if ((text.trim().isEmpty && _pendingImages.isEmpty) ||
        _controller.generating ||
        _controller.analyzingImages ||
        _controller.generatingPlayerReply) {
      return;
    }
    final images = _pendingImages;
    _input.clear();
    setState(() => _pendingImages = const []);
    await _controller.sendUserMessage(text, attachments: images);
  }

  Future<void> _pickImages() async {
    if (_pickingImages ||
        _controller.generating ||
        _controller.analyzingImages) {
      return;
    }
    final settings = _controller.settings.visionSettings;
    if (!settings.enabled) {
      _voiceError('请先在应用设置 → 看图能力中启用并配置视觉服务。');
      return;
    }
    setState(() => _pickingImages = true);
    try {
      final images = await _imagePreprocessor.pickAndPrepare(settings);
      if (!mounted || images.isEmpty) return;
      for (final image in _pendingImages) {
        final file = File(image.localPath);
        if (file.existsSync()) file.deleteSync();
      }
      setState(() => _pendingImages = images);
    } catch (error) {
      _voiceError('选择图片失败：$error');
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
  }

  void _removePendingImage(int index) {
    final image = _pendingImages[index];
    final file = File(image.localPath);
    if (file.existsSync()) file.deleteSync();
    setState(() {
      _pendingImages = [..._pendingImages]..removeAt(index);
    });
  }

  Future<void> _submitFreeChoice() async {
    final text = _input.text;
    if ((text.trim().isEmpty && _pendingImages.isEmpty) ||
        _controller.generating ||
        _controller.analyzingImages ||
        _controller.generatingChoices ||
        _controller.compressingContext) {
      return;
    }
    final images = _pendingImages;
    _input.clear();
    setState(() => _pendingImages = const []);
    await _controller.submitFreeChoice(text, attachments: images);
  }

  Future<void> _thinkPlayerReply() async {
    if (_controller.generating ||
        _controller.generatingPlayerReply ||
        _controller.compressingContext) {
      return;
    }
    final selection = await showPlayerReplyToneDialog(
      context,
      initialTone: _replyTone,
    );
    if (selection == null || !mounted) return;
    setState(() => _replyTone = selection.tone);
    try {
      final suggestion = await _controller.generatePlayerReply(
        tone: selection.tone,
        customTone: selection.customTone,
        draft: _input.text,
      );
      if (!mounted) return;
      _input.value = TextEditingValue(
        text: suggestion,
        selection: TextSelection.collapsed(offset: suggestion.length),
      );
      _inputFocus.requestFocus();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已填入输入框，你可以修改后再发送。')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AI 思考失败：$error')));
    }
  }

  Future<void> _editSave() async {
    final updated = await Navigator.push<SaveSlot>(
      context,
      MaterialPageRoute(
        builder: (_) => SaveEditorScreen(initialSave: _controller.save),
      ),
    );
    if (updated != null) {
      await widget.saveRepository.upsert(updated);
      await _controller.reload();
      await _controller.ensureChoices();
    }
  }

  Future<void> _openCharacters() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterListScreen(
          save: _controller.save,
          repository: widget.saveRepository,
          characterCardRepository: widget.characterCardRepository,
          settingsRepository: widget.settingsRepository,
        ),
      ),
    );
    await _controller.reload();
  }

  Future<void> _openLorebook() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LorebookScreen(
          save: _controller.save,
          repository: widget.saveRepository,
        ),
      ),
    );
    await _controller.reload();
  }

  Future<void> _openMemory() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MemoryScreen(
          save: _controller.save,
          repository: widget.saveRepository,
          onGenerate: _controller.generateMemorySummary,
        ),
      ),
    );
    await _controller.reload();
  }

  Future<void> _openApiSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ApiSettingsScreen(
          apiRepository: widget.apiRepository,
          settingsRepository: widget.settingsRepository,
          aiService: widget.aiService,
        ),
      ),
    );
    await _controller.refreshProfiles();
  }

  Future<void> _editMessage(ChatMessage message) async {
    final text = TextEditingController(text: message.content);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑消息'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: text,
            minLines: 5,
            maxLines: 16,
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    text.dispose();
    if (result != null) await _controller.editMessage(message.id, result);
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除消息？'),
        content: const Text('此操作不会删除其后消息。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.deleteMessage(message.id);
  }

  Future<void> _continueFrom(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从这里继续？'),
        content: const Text('该消息之后的所有消息将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.continueFrom(message.id);
  }

  void _handleMessageAction(ChatMessage message, MessageAction action) {
    switch (action) {
      case MessageAction.copy:
        break;
      case MessageAction.edit:
        _editMessage(message);
      case MessageAction.delete:
        _deleteMessage(message);
      case MessageAction.regenerate:
        _controller.regenerate(message.id);
      case MessageAction.continueFrom:
        _continueFrom(message);
    }
  }

  Widget _navigation({bool closeDrawer = false}) {
    void run(Future<void> Function() action) {
      if (closeDrawer) Navigator.pop(context);
      action();
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(
          leading: const SkinIcon(Icons.people_outline),
          title: const Text('角色'),
          subtitle: Text('${_controller.save.characters.length} 个'),
          onTap: () => run(_openCharacters),
        ),
        ListTile(
          leading: const SkinIcon(Icons.public),
          title: const Text('世界与剧情'),
          onTap: () => run(_editSave),
        ),
        ListTile(
          leading: const SkinIcon(Icons.menu_book_outlined),
          title: const Text('世界书'),
          subtitle: Text('${_controller.save.lorebook.length} 条'),
          onTap: () => run(_openLorebook),
        ),
        ListTile(
          leading: const SkinIcon(Icons.psychology_outlined),
          title: const Text('长期记忆'),
          onTap: () => run(_openMemory),
        ),
        ListTile(
          leading: const SkinIcon(Icons.visibility_outlined),
          title: const Text('Prompt 预览'),
          onTap: () {
            if (closeDrawer) Navigator.pop(context);
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => PromptPreviewScreen(
                  save: _controller.save,
                  settings: _controller.settings,
                ),
              ),
            );
          },
        ),
        const Divider(),
        ListTile(
          leading: const SkinIcon(Icons.hub_outlined),
          title: const Text('AI API'),
          onTap: () => run(_openApiSettings),
        ),
        ListTile(
          leading: const SkinIcon(Icons.palette_outlined),
          title: const Text('外观与皮肤'),
          onTap: () => run(() => openSkinGallery(context)),
        ),
      ],
    );
  }

  Widget _messageList() {
    if (_controller.save.messages.isEmpty) {
      return const Center(child: Text('输入一句话，开始故事。'));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      itemCount: _controller.save.messages.length,
      itemBuilder: (context, index) {
        final message = _controller.save.messages[index];
        final streaming =
            _controller.generating &&
            index == _controller.save.messages.length - 1 &&
            message.role == ChatRole.assistant;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MessageBubble(
            message: message,
            isStreaming: streaming,
            onAction: (action) => _handleMessageAction(message, action),
            onRetry: () => _controller.regenerate(message.id),
            isSpeaking:
                _voice.speakingMessageId == message.id &&
                _voice.speechState == TextToSpeechState.playing,
            isSpeechLoading:
                _voice.speakingMessageId == message.id &&
                _voice.speechState == TextToSpeechState.generating,
            onSpeak: message.role == ChatRole.assistant
                ? () => _speakMessage(message)
                : null,
            onRetryVision: message.hasImages
                ? () => _controller.retryVision(message.id)
                : null,
            showVisionDebug: _controller.settings.visionSettings.debugMode,
          ),
        );
      },
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pendingImages.isNotEmpty) ...[
                SizedBox(
                  height: 86,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pendingImages.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final attachment = _pendingImages[index];
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(attachment.localPath),
                              width: 86,
                              height: 86,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            right: 2,
                            top: 2,
                            child: IconButton.filled(
                              visualDensity: VisualDensity.compact,
                              iconSize: 15,
                              tooltip: '移除图片',
                              onPressed: () => _removePendingImage(index),
                              icon: const SkinIcon(Icons.close),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _send();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  minLines: 2,
                  maxLines: 7,
                  enabled:
                      !_controller.generating &&
                      !_controller.analyzingImages &&
                      !_controller.generatingPlayerReply &&
                      !_controller.compressingContext,
                  decoration: InputDecoration(
                    hintText: '输入行动、对白或 OOC 指令…',
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerLow,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '选择图片（最多 3 张）',
                    onPressed: _pickingImages ? null : _pickImages,
                    icon: _pickingImages
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const SkinIcon(Icons.add_photo_alternate_outlined),
                  ),
                  if (_controller.generatingPlayerReply)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'AI 帮我想（当前：${_replyTone.label}）',
                      onPressed:
                          _controller.generating ||
                              _controller.compressingContext
                          ? null
                          : _thinkPlayerReply,
                      icon: const SkinIcon(Icons.psychology_alt_outlined),
                    ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _micTooltip(),
                    onPressed:
                        _controller.generatingPlayerReply ||
                            _controller.compressingContext
                        ? null
                        : _toggleMicrophone,
                    color: _micColor(Theme.of(context).colorScheme),
                    icon: _micIcon(),
                  ),
                  const SizedBox(width: 6),
                  if (_controller.generating || _controller.analyzingImages)
                    FilledButton.icon(
                      onPressed: _stopGenerationAndSpeech,
                      icon: const SkinIcon(Icons.stop),
                      label: Text(_controller.analyzingImages ? '停止识图' : '停止'),
                    )
                  else
                    IconButton.filled(
                      tooltip: '发送',
                      onPressed: _controller.compressingContext ? null : _send,
                      icon: const SkinIcon(Icons.send),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choiceBar() {
    final choices = _controller.save.pendingChoices;
    final busy =
        _controller.generating ||
        _controller.analyzingImages ||
        _controller.generatingChoices ||
        _controller.compressingContext;
    final maxChoiceHeight = (MediaQuery.sizeOf(context).height * 0.30).clamp(
      150.0,
      320.0,
    );
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: CollapsibleChoicePanel(
            title: _controller.generating
                ? '剧情正在发展……'
                : _controller.compressingContext
                ? '正在压缩并保存上下文……'
                : _controller.refiningChoices
                ? '正在细化台词与角色动作……'
                : _controller.generatingChoices
                ? '正在生成下一轮选项……'
                : '选择下一步行动（${choices.length} 项）',
            busy: busy,
            action: _controller.generating
                ? TextButton.icon(
                    onPressed: _stopGenerationAndSpeech,
                    icon: const SkinIcon(Icons.stop, size: 18),
                    label: const Text('停止'),
                  )
                : IconButton(
                    tooltip: '重新生成选项',
                    onPressed: _controller.generatingChoices
                        ? null
                        : _controller.regenerateChoices,
                    icon: const SkinIcon(Icons.refresh),
                  ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pendingImages.isNotEmpty) ...[
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pendingImages.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final attachment = _pendingImages[index];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                File(attachment.localPath),
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: IconButton.filled(
                                visualDensity: VisualDensity.compact,
                                iconSize: 14,
                                tooltip: '移除图片',
                                onPressed: busy
                                    ? null
                                    : () => _removePendingImage(index),
                                icon: const SkinIcon(Icons.close),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Focus(
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.enter &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            _submitFreeChoice();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _input,
                          focusNode: _inputFocus,
                          minLines: 1,
                          maxLines: 4,
                          enabled: !busy,
                          decoration: const InputDecoration(
                            hintText: '自由输入台词或动作，不使用预设选项',
                            prefixIcon: SkinIcon(Icons.edit_note),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '添加图片',
                      onPressed: busy || _pickingImages ? null : _pickImages,
                      icon: _pickingImages
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const SkinIcon(Icons.add_photo_alternate_outlined),
                    ),
                    IconButton(
                      tooltip: _micTooltip(),
                      onPressed: busy ? null : _toggleMicrophone,
                      color: _micColor(Theme.of(context).colorScheme),
                      icon: _micIcon(),
                    ),
                    IconButton.filled(
                      tooltip: '发送自由输入',
                      onPressed: busy ? null : _submitFreeChoice,
                      icon: const SkinIcon(Icons.send),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: busy || choices.isEmpty
                        ? null
                        : _controller.refineChoices,
                    icon: const SkinIcon(Icons.auto_awesome),
                    label: Text(
                      _controller.refiningChoices
                          ? '正在细化……'
                          : '细化选项：生成具体台词＋角色动作',
                    ),
                  ),
                ),
                if (_controller.choiceError != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _controller.choiceError!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                if (choices.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxChoiceHeight),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: choices.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final choice = choices[index];
                        return SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => _controller.selectChoice(choice),
                            style: OutlinedButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            child: Text('${index + 1}. $choice'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chatBody() => Column(
    children: [
      Expanded(child: ThemeBackground(chat: true, child: _messageList())),
      if (_controller.compressingContext)
        const ListTile(
          dense: true,
          leading: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('正在把本轮剧情压缩为长期记忆……'),
        )
      else if (_controller.contextCompressionError case final error?)
        ListTile(
          dense: true,
          leading: SkinIcon(
            Icons.warning_amber,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(error, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      if (_controller.save.playMode == PlayMode.choice)
        _choiceBar()
      else
        _inputBar(),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_controller.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Scaffold(
          drawer: wide ? null : Drawer(child: _navigation(closeDrawer: true)),
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_controller.save.coverImage case final cover?) ...[
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: File(cover).existsSync()
                        ? FileImage(File(cover))
                        : null,
                    child: File(cover).existsSync()
                        ? null
                        : const SkinIcon(Icons.image_not_supported, size: 18),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(_controller.save.name)),
                const SizedBox(width: 8),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_controller.save.playMode.label),
                ),
              ],
            ),
            actions: [
              if (_controller.profiles.isNotEmpty)
                PopupMenuButton<ApiProfile>(
                  tooltip: '选择 AI 配置',
                  initialValue: _controller.selectedProfile,
                  onSelected: _controller.selectProfile,
                  itemBuilder: (_) => _controller.profiles
                      .map(
                        (profile) => PopupMenuItem(
                          value: profile,
                          child: Text(profile.name),
                        ),
                      )
                      .toList(),
                  icon: const SkinIcon(Icons.hub_outlined),
                )
              else
                IconButton(
                  tooltip: '配置 AI API',
                  onPressed: _openApiSettings,
                  icon: const SkinIcon(Icons.warning_amber),
                ),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    SizedBox(width: 260, child: _navigation()),
                    const VerticalDivider(width: 1),
                    Expanded(child: _chatBody()),
                  ],
                )
              : _chatBody(),
        );
      },
    );
  }
}
