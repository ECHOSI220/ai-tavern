import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/api_profile.dart';
import '../../models/rule_reference.dart';
import '../../models/trpg_models.dart';
import '../../models/trpg_dice_models.dart';
import '../../models/campaign_models.dart';
import '../../models/character.dart';
import '../../repositories/api_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/trpg_session_repository.dart';
import '../../repositories/campaign_repository.dart';
import '../../services/ai_service.dart';
import '../../services/trpg/ai_gm_service.dart';
import '../../services/trpg/campaign_service.dart';
import '../../services/trpg/campaign_opening_briefing.dart';
import '../../services/trpg/trpg_session_service.dart';
import '../character_cards/character_card_screen.dart';
import '../rule_library/rule_library_screen.dart';

class SoloSetupScreen extends StatefulWidget {
  const SoloSetupScreen({
    required this.repository,
    required this.apiRepository,
    required this.settingsRepository,
    required this.aiService,
    required this.characterRepository,
    this.campaignRepository,
    this.initialCampaign,
    super.key,
  });
  final TRPGSessionRepository repository;
  final ApiRepository apiRepository;
  final SettingsRepository settingsRepository;
  final AiService aiService;
  final CharacterCardRepository characterRepository;
  final CampaignRepository? campaignRepository;
  final CampaignDocument? initialCampaign;
  @override
  State<SoloSetupScreen> createState() => _SoloSetupScreenState();
}

class _SoloSetupScreenState extends State<SoloSetupScreen> {
  static const _uuid = Uuid();
  final _campaigns = const CampaignService();
  final _player = TextEditingController(text: '玩家');
  final _name = TextEditingController();
  final _background = TextEditingController();
  final _avatar = TextEditingController();
  final Map<String, double> _stats = {
    'STR': 10,
    'DEX': 10,
    'INT': 10,
    'PER': 10,
    'CHA': 10,
  };
  int _step = 0;
  double _maxHp = 20;
  Campaign? _campaign;
  CampaignDocument? _campaignDocument;
  List<ApiProfile> _profiles = const [];
  List<CampaignDocument> _campaignDocuments = const [];
  final List<PlayerCharacter> _aiPlayers = [];
  final _random = Random();
  String? _profileId;
  bool _saving = false;
  DiceRulePackageType _rulePackage = DiceRulePackageType.genericD20;

  @override
  void initState() {
    super.initState();
    if (widget.initialCampaign != null) {
      _campaignDocument = widget.initialCampaign;
      _campaign = widget.initialCampaign!.toLegacy();
      _rulePackage = _suggestedRulePackage(widget.initialCampaign!);
    } else {
      _campaign = _campaigns.builtInCampaigns[1];
    }
    _load();
  }

  Future<void> _load() async {
    final profiles = await widget.apiRepository.getAll();
    final settings = await widget.settingsRepository.load();
    final documents =
        await widget.campaignRepository?.getAll() ?? const <CampaignDocument>[];
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _profileId =
          profiles.any((item) => item.id == settings.defaultApiProfileId)
          ? settings.defaultApiProfileId
          : profiles.firstOrNull?.id;
      if (widget.initialCampaign != null) {
        _campaignDocument = widget.initialCampaign;
        _campaign = widget.initialCampaign!.toLegacy();
      } else if (documents.isNotEmpty) {
        _campaignDocuments = documents;
        _campaignDocument = documents.first;
        _campaign = documents.first.toLegacy();
        _rulePackage = _suggestedRulePackage(documents.first);
      }
    });
  }

  Future<void> _importAiPlayer() async {
    if (_aiPlayers.length >= 4) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('最多植入 4 个 AI 玩家角色')));
      }
      return;
    }
    final character = await Navigator.push<Character>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterCardScreen(
          repository: widget.characterRepository,
          settingsRepository: widget.settingsRepository,
          selectForSave: true,
        ),
      ),
    );
    if (character == null || !mounted) return;
    setState(() => _aiPlayers.add(_aiPlayerFromCharacter(character)));
  }

  void _addRandomAiPlayer() {
    if (_aiPlayers.length >= 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('最多植入 4 个 AI 玩家角色')));
      return;
    }
    setState(() => _aiPlayers.add(_randomAiPlayer()));
  }

  PlayerCharacter _aiPlayerFromCharacter(Character character) {
    final id = _uuid.v4();
    final playerId = _uuid.v4();
    final description = [
      character.description,
      character.appearance,
      character.background,
    ].where((value) => value.trim().isNotEmpty).join('\n');
    final personality = [
      character.personality,
      character.speakingStyle,
      character.goals,
    ].where((value) => value.trim().isNotEmpty).join('\n');
    return PlayerCharacter(
      id: id,
      playerId: playerId,
      name: character.name,
      avatar: character.avatar,
      description: description,
      background: character.background,
      personality: personality,
      stats: const {'STR': 10, 'DEX': 10, 'INT': 10, 'PER': 10, 'CHA': 10},
      hp: 20,
      maxHp: 20,
      metadata: {'isAiControlled': true, 'sourceCharacterId': character.id},
    );
  }

  PlayerCharacter _randomAiPlayer() {
    const names = [
      '阿黛尔',
      '铁锤',
      '小满',
      '夜枭',
      '白鸦',
      '老陈',
      '铃',
      '罗恩',
      '梅',
      '阿岚',
      '柯林',
      '苏',
    ];
    const backgrounds = [
      '流浪佣兵',
      '前酒馆老板',
      '落魄贵族',
      '神秘学者',
      '街头盗贼',
      '边境猎人',
      '退役军官',
      '吟游诗人',
    ];
    const personalities = [
      '谨慎多疑，但认定同伴后非常可靠。',
      '大大咧咧，喜欢用玩笑缓解紧张。',
      '沉默寡言，观察力很强，很少表露情绪。',
      '好奇心重，遇到未知事物总想先碰一下。',
      '嘴硬心软，嘴上拒绝但总会帮忙。',
      '务实冷静，讨厌无意义的牺牲。',
    ];
    final name = names[_random.nextInt(names.length)];
    final background = backgrounds[_random.nextInt(backgrounds.length)];
    final personality = personalities[_random.nextInt(personalities.length)];
    final maxHp = 14 + _random.nextInt(12);
    int stat() => 8 + _random.nextInt(9);
    return PlayerCharacter(
      id: _uuid.v4(),
      playerId: _uuid.v4(),
      name: name,
      background: background,
      personality: personality,
      description: '随机生成的一名$background，$personality',
      stats: {
        'STR': stat(),
        'DEX': stat(),
        'INT': stat(),
        'PER': stat(),
        'CHA': stat(),
      },
      hp: maxHp,
      maxHp: maxHp,
      metadata: {'isAiControlled': true},
    );
  }

  Future<void> _finish() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写角色名')));
      return;
    }
    setState(() => _saving = true);
    final session = await TRPGSessionService(widget.repository).createSolo(
      campaign: _campaign!,
      campaignDocument: _campaignDocument,
      playerName: _player.text.trim().isEmpty ? '玩家' : _player.text.trim(),
      characterName: _name.text.trim(),
      characterBackground: _background.text.trim(),
      characterAvatar: _avatar.text.trim().isEmpty ? null : _avatar.text.trim(),
      stats: _stats.map((key, value) => MapEntry(key, value.round())),
      maxHp: _maxHp.round(),
      gmProviderConfigRef: _profileId,
      aiPlayerCharacters: _aiPlayers,
      rulePackage: _rulePackage,
    );
    var initialized = session;
    final profile = _profiles
        .where((item) => item.id == _profileId)
        .firstOrNull;
    // Holy Grail War creates the private Master/Servant dossier in its own
    // lobby before any public AI narration. Running the generic opener here
    // used to produce a vague "decide why you fight" message too early.
    final holyGrail =
        _campaignDocument?.campaignType == CampaignType.holyGrailWar;
    if (profile != null && !holyGrail) {
      try {
        final apiKey = await widget.apiRepository.readApiKey(profile.id);
        initialized = await AIGMService(widget.aiService).initializeSession(
          session: session,
          profile: profile,
          apiKey: apiKey,
          onToolMutation: widget.repository.upsert,
        );
        await widget.repository.upsert(initialized);
      } catch (_) {
        // Session remains playable and recoverable even if opening generation
        // is temporarily unavailable.
      }
    }
    if (mounted) Navigator.pop(context, initialized);
  }

  @override
  void dispose() {
    _player.dispose();
    _name.dispose();
    _background.dispose();
    _avatar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lockedCampaign = widget.initialCampaign != null;
    final steps = <Step>[
      if (!lockedCampaign) _campaignStep(),
      _characterStep(),
      _aiPlayersStep(),
      _settingsStep(),
      _confirmStep(),
    ];
    final lastStep = steps.length - 1;
    return Scaffold(
      appBar: AppBar(title: const Text('新建单人跑团')),
      body: Stepper(
        currentStep: _step,
        onStepContinue: _step == lastStep
            ? _finish
            : () => setState(() => _step++),
        onStepCancel: _step == 0 ? null : () => setState(() => _step--),
        controlsBuilder: (context, details) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              FilledButton(
                onPressed: _saving ? null : details.onStepContinue,
                child: Text(_step == lastStep ? '创建并开始' : '下一步'),
              ),
              if (_step > 0) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: details.onStepCancel,
                  child: const Text('上一步'),
                ),
              ],
            ],
          ),
        ),
        steps: steps,
      ),
    );
  }

  Step _campaignStep() => Step(
    title: const Text('选择剧本'),
    isActive: _step >= 0,
    content: Column(
      children: [
        ..._campaignDocuments.map((document) {
          final selected = document.id == _campaign?.id;
          return Card(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: ListTile(
              onTap: () => setState(() {
                _campaignDocument = document;
                _campaign = document.toLegacy();
                _rulePackage = _suggestedRulePackage(document);
              }),
              leading: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
              ),
              title: Text(document.title),
              subtitle: Text(
                '${document.description}\n${document.recommendedPlayers}人 · ${document.estimatedLength}',
              ),
              isThreeLine: true,
            ),
          );
        }),
        ..._campaigns.builtInCampaigns
            .where(
              (value) => !_campaignDocuments.any(
                (document) => document.id == value.id,
              ),
            )
            .map((campaign) {
              final selected = campaign.id == _campaign?.id;
              return Card(
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: ListTile(
                  onTap: () => setState(() {
                    _campaign = campaign;
                    _campaignDocument = null;
                    _rulePackage = DiceRulePackageType.genericD20;
                  }),
                  leading: Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                  ),
                  title: Text(campaign.title),
                  subtitle: Text(campaign.description),
                ),
              );
            }),
      ],
    ),
  );

  Step _characterStep() => Step(
    title: const Text('创建角色'),
    isActive: true,
    content: Column(
      children: [
        TextField(
          controller: _player,
          decoration: const InputDecoration(labelText: '玩家称呼'),
        ),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: '角色名'),
        ),
        TextField(
          controller: _background,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(labelText: '背景'),
        ),
        TextField(
          controller: _avatar,
          decoration: const InputDecoration(
            labelText: '头像路径（可选）',
            helperText: '第一版保存本地图片路径，后续可增加相册选择器',
          ),
        ),
        ..._stats.entries.map(
          (entry) => Row(
            children: [
              SizedBox(width: 42, child: Text(entry.key)),
              Expanded(
                child: Slider(
                  min: 6,
                  max: 18,
                  divisions: 12,
                  label: entry.value.round().toString(),
                  value: entry.value,
                  onChanged: (value) =>
                      setState(() => _stats[entry.key] = value),
                ),
              ),
              Text('${entry.value.round()}'),
            ],
          ),
        ),
        Row(
          children: [
            const SizedBox(width: 68, child: Text('MaxHP')),
            Expanded(
              child: Slider(
                min: 10,
                max: 40,
                divisions: 30,
                label: _maxHp.round().toString(),
                value: _maxHp,
                onChanged: (value) => setState(() => _maxHp = value),
              ),
            ),
            Text('${_maxHp.round()}'),
          ],
        ),
      ],
    ),
  );

  Step _aiPlayersStep() => Step(
    title: const Text('植入 AI 玩家'),
    isActive: true,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListTile(
          leading: Icon(Icons.smart_toy_outlined),
          title: Text('AI 玩家角色'),
          subtitle: Text('像普通玩家一样行动的植入角色，与 GM 分开对话、独立思考'),
        ),
        if (_aiPlayers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('尚未植入 AI 玩家，可跳过，或从角色卡导入 / 随机生成。'),
          ),
        ..._aiPlayers.map(
          (player) => Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.smart_toy_outlined),
              ),
              title: Text(player.name),
              subtitle: Text(
                player.background.isEmpty
                    ? player.description
                    : player.background,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: '移除',
                onPressed: () => setState(() => _aiPlayers.remove(player)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _importAiPlayer,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('从角色卡导入'),
            ),
            FilledButton.icon(
              onPressed: _addRandomAiPlayer,
              icon: const Icon(Icons.casino_outlined),
              label: const Text('随机生成一个'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('最多 4 个 · 已选 ${_aiPlayers.length} 个'),
      ],
    ),
  );

  Step _settingsStep() => Step(
    title: const Text('跑团设置'),
    isActive: true,
    content: Column(
      children: [
        if (_rulePackage == DiceRulePackageType.holyGrailWar)
          const ListTile(
            leading: Icon(Icons.auto_awesome),
            title: Text('圣杯战争专用规则'),
            subtitle: Text('御主、从者、令咒、宝具与阵营情报隔离'),
          )
        else
          DropdownButtonFormField<DiceRulePackageType>(
            key: const ValueKey('solo-rule-package'),
            initialValue: _rulePackage,
            decoration: const InputDecoration(
              labelText: '跑团规则',
              prefixIcon: Icon(Icons.rule_outlined),
            ),
            items: const [
              DropdownMenuItem(
                value: DiceRulePackageType.genericD20,
                child: Text('通用简易规则 · D20'),
              ),
              DropdownMenuItem(
                value: DiceRulePackageType.dnd,
                child: Text('D&D 5E · D20'),
              ),
              DropdownMenuItem(
                value: DiceRulePackageType.coc,
                child: Text('COC 7版 · D100'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _rulePackage = value);
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('open-rules-from-solo-setup'),
            onPressed: _openSelectedRuleReference,
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('查看所选规则速查'),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _profileId,
          decoration: const InputDecoration(labelText: 'AI GM 模型'),
          items: _profiles
              .map(
                (profile) => DropdownMenuItem(
                  value: profile.id,
                  child: Text('${profile.name} · ${profile.model}'),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _profileId = value),
        ),
        if (_profiles.isEmpty)
          const ListTile(
            leading: Icon(Icons.warning_amber),
            title: Text('未配置 API'),
            subtitle: Text('可先创建存档，但 AI GM 需在设置中配置 API 后使用。'),
          ),
      ],
    ),
  );

  Step _confirmStep() => Step(
    title: const Text('确认创建'),
    isActive: true,
    content: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _campaign!.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '角色：${_name.text.isEmpty ? '未命名' : _name.text}\n'
              'AI 玩家：${_aiPlayers.isEmpty ? '无' : _aiPlayers.map((player) => player.name).join('、')}\n'
              '规则：${_rulePackageLabel(_rulePackage)}\n'
              'AI GM：${_profiles.where((item) => item.id == _profileId).firstOrNull?.model ?? '待配置'}',
            ),
            const Divider(height: 28),
            Text(
              '开始前说明',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              const CampaignOpeningBriefing().build(
                campaign: _campaign!,
                document: _campaignDocument,
                playerCharacters: [
                  _name.text.isEmpty ? '未命名角色' : _name.text,
                  ..._aiPlayers.map((player) => player.name),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  DiceRulePackageType _suggestedRulePackage(CampaignDocument document) {
    if (document.campaignType == CampaignType.holyGrailWar) {
      return DiceRulePackageType.holyGrailWar;
    }
    final rule = document.ruleSystem.toLowerCase();
    if (rule.contains('coc') || rule.contains('克苏鲁')) {
      return DiceRulePackageType.coc;
    }
    if (rule.contains('d&d') || rule.contains('dnd') || rule.contains('5e')) {
      return DiceRulePackageType.dnd;
    }
    return DiceRulePackageType.genericD20;
  }

  String _rulePackageLabel(DiceRulePackageType package) => switch (package) {
    DiceRulePackageType.genericD20 => '通用简易规则 · D20',
    DiceRulePackageType.dnd => 'D&D 5E · D20',
    DiceRulePackageType.coc => 'COC 7版 · D100',
    DiceRulePackageType.holyGrailWar => '圣杯战争专用规则',
    DiceRulePackageType.dicePool => '骰池规则',
    DiceRulePackageType.custom => '自定义规则',
  };

  void _openSelectedRuleReference() {
    final system = switch (_rulePackage) {
      DiceRulePackageType.coc => RuleReferenceSystem.coc7,
      DiceRulePackageType.dnd => RuleReferenceSystem.dnd5e,
      _ => RuleReferenceSystem.quickStart,
    };
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RuleLibraryScreen(initialSystem: system),
      ),
    );
  }
}
