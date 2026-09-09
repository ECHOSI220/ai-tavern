import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/campaign_models.dart';
import '../../models/trpg_models.dart';
import '../../models/trpg_presentation_models.dart';
import '../../repositories/campaign_repository.dart';
import '../../repositories/character_card_repository.dart';
import '../../services/trpg/campaign_codec_service.dart';

class CampaignEditorScreen extends StatefulWidget {
  const CampaignEditorScreen({
    required this.initial,
    required this.repository,
    required this.characterRepository,
    super.key,
  });
  final CampaignDocument initial;
  final CampaignRepository repository;
  final CharacterCardRepository characterRepository;
  @override
  State<CampaignEditorScreen> createState() => _CampaignEditorScreenState();
}

class _CampaignEditorScreenState extends State<CampaignEditorScreen> {
  static const _codec = CampaignCodecService();
  late CampaignDocument _campaign;
  late final TextEditingController _title,
      _description,
      _opening,
      _systemPrompt;
  late final TextEditingController _tags,
      _players,
      _length,
      _rule,
      _theme,
      _tone,
      _author;
  int _section = 0;
  bool _saving = false;
  static const _labels = [
    '基本信息',
    '开场',
    '章节',
    '地点',
    'NPC',
    '任务',
    '线索',
    '物品',
    '阵营',
    '遭遇',
    '秘密',
    '结局',
    'AI主持设置',
    '演出与音频',
  ];

  @override
  void initState() {
    super.initState();
    _campaign = widget.initial;
    _title = TextEditingController(text: _campaign.title);
    _description = TextEditingController(text: _campaign.description);
    _opening = TextEditingController(text: _campaign.opening);
    _systemPrompt = TextEditingController(text: _campaign.systemPrompt);
    _tags = TextEditingController(text: _campaign.tags.join('，'));
    _players = TextEditingController(text: _campaign.recommendedPlayers);
    _length = TextEditingController(text: _campaign.estimatedLength);
    _rule = TextEditingController(text: _campaign.ruleSystem);
    _theme = TextEditingController(text: _campaign.theme);
    _tone = TextEditingController(text: _campaign.tone);
    _author = TextEditingController(text: _campaign.author);
  }

  void _sync() {
    _campaign = _campaign.copyWith(
      title: _title.text.trim(),
      description: _description.text.trim(),
      opening: _opening.text,
      systemPrompt: _systemPrompt.text,
      tags: _tags.text
          .split(RegExp('[,，]'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      recommendedPlayers: _players.text.trim(),
      estimatedLength: _length.text.trim(),
      ruleSystem: _rule.text.trim(),
      theme: _theme.text.trim(),
      tone: _tone.text.trim(),
      author: _author.text.trim(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _save() async {
    _sync();
    final validation = _codec.validateCampaign(_campaign);
    if (!validation.isValid) {
      _showIssues(validation);
      return;
    }
    setState(() => _saving = true);
    await widget.repository.upsert(_campaign);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('剧本已保存')));
  }

  void _showIssues(CampaignValidationResult result) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(result.isValid ? '检查完成' : '发现错误'),
      content: SizedBox(
        width: 620,
        child: ListView(
          shrinkWrap: true,
          children: result.issues.isEmpty
              ? [const Text('没有发现问题。')]
              : result.issues
                    .map(
                      (issue) => ListTile(
                        dense: true,
                        leading: Icon(
                          issue.isWarning
                              ? Icons.warning_amber
                              : Icons.error_outline,
                        ),
                        title: Text(issue.message),
                      ),
                    )
                    .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  Future<void> _importCharacter() async {
    final characters = await widget.characterRepository.getAll();
    if (!mounted) return;
    if (characters.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('角色卡库为空')));
      return;
    }
    final selected = await showDialog<(int, CampaignNpcRole)?>(
      context: context,
      builder: (context) {
        var role = CampaignNpcRole.npc;
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('从酒馆角色卡导入'),
            content: SizedBox(
              width: 520,
              height: 430,
              child: Column(
                children: [
                  DropdownButtonFormField<CampaignNpcRole>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: '跑团身份'),
                    items: CampaignNpcRole.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setLocal(() => role = value!),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: characters.length,
                      itemBuilder: (_, index) => ListTile(
                        title: Text(characters[index].name),
                        subtitle: Text(
                          characters[index].personality,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, (index, role)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected == null) return;
    final profile = TRPGNPCProfile.fromCharacter(
      characters[selected.$1],
      role: selected.$2,
    );
    setState(
      () => _campaign = _campaign.copyWith(npcs: [..._campaign.npcs, profile]),
    );
  }

  Future<void> _rawEdit(
    String title,
    Object value,
    void Function(Object decoded) apply,
  ) async {
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(value),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title · JSON 编辑'),
        content: SizedBox(
          width: 760,
          height: 520,
          child: TextField(
            controller: controller,
            expands: true,
            maxLines: null,
            minLines: null,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    try {
      apply(jsonDecode(result));
      setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('JSON 无效：$error')));
      }
    }
  }

  void _preview(bool gm) {
    _sync();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(gm ? 'GM 视角预览' : '玩家视角预览'),
        content: SizedBox(
          width: 760,
          height: 560,
          child: ListView(
            children: [
              Text(
                _campaign.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(_campaign.description),
              const Divider(),
              Text('开场', style: Theme.of(context).textTheme.titleLarge),
              Text(_campaign.opening),
              Text('已知地点', style: Theme.of(context).textTheme.titleLarge),
              ..._campaign.locations
                  .where((value) => gm || (!value.hidden && value.discovered))
                  .map(
                    (value) => ListTile(
                      title: Text(value.name),
                      subtitle: Text(value.description),
                    ),
                  ),
              Text('人物', style: Theme.of(context).textTheme.titleLarge),
              ..._campaign.npcs
                  .where((value) => gm || value.knownToPlayers)
                  .map(
                    (value) => ListTile(
                      title: Text(value.name),
                      subtitle: Text(
                        gm && value.privateNotes.isNotEmpty
                            ? '${value.description}\nGM: ${value.privateNotes}'
                            : value.description,
                      ),
                    ),
                  ),
              Text('线索', style: Theme.of(context).textTheme.titleLarge),
              ..._campaign.clues
                  .where(
                    (value) =>
                        gm ||
                        (value.discovered &&
                            value.visibility == InformationVisibility.public),
                  )
                  .map(
                    (value) => ListTile(
                      title: Text(value.name),
                      subtitle: Text(value.description),
                    ),
                  ),
              if (gm) ...[
                Text('GM 秘密', style: Theme.of(context).textTheme.titleLarge),
                ..._campaign.secrets.map(
                  (value) => ListTile(title: Text(value)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text('编辑剧本 · ${_title.text.isEmpty ? '未命名' : _title.text}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'player') _preview(false);
              if (value == 'gm') _preview(true);
              if (value == 'validate') {
                _sync();
                _showIssues(_codec.validateCampaign(_campaign));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'player', child: Text('玩家视角预览')),
              PopupMenuItem(value: 'gm', child: Text('GM视角预览')),
              PopupMenuItem(value: 'validate', child: Text('检查剧本')),
            ],
          ),
          IconButton(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            tooltip: '保存',
          ),
        ],
      ),
      drawer: MediaQuery.sizeOf(context).width < 800
          ? Drawer(child: SafeArea(child: _navigation(true)))
          : null,
      body: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Row(
          children: [
            if (MediaQuery.sizeOf(context).width >= 800)
              SizedBox(
                width: 240,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  child: _navigation(false),
                ),
              ),
            Expanded(child: _content()),
          ],
        ),
      ),
    ),
  );

  Widget _navigation(bool close) => ListView.builder(
    itemCount: _labels.length,
    itemBuilder: (_, index) => ListTile(
      selected: _section == index,
      leading: Icon(_icon(index)),
      title: Text(_labels[index]),
      onTap: () {
        setState(() => _section = index);
        if (close) Navigator.pop(context);
      },
    ),
  );

  IconData _icon(int index) => [
    Icons.info_outline,
    Icons.play_arrow,
    Icons.account_tree_outlined,
    Icons.place_outlined,
    Icons.people_outline,
    Icons.task_alt,
    Icons.search,
    Icons.inventory_2_outlined,
    Icons.flag_outlined,
    Icons.security_outlined,
    Icons.visibility_off_outlined,
    Icons.flag_circle_outlined,
    Icons.smart_toy_outlined,
  ][index];

  Widget _content() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: _sectionContent(),
      ),
    ),
  );

  List<Widget> _sectionContent() {
    switch (_section) {
      case 0:
        return [
          _field(_title, 'Title'),
          _field(_description, 'Description', lines: 5),
          _field(_tags, 'Tags（逗号分隔）'),
          _field(_players, 'Recommended Players'),
          _field(_length, 'Estimated Length'),
          _field(_rule, 'Rule System'),
          _field(_theme, 'Theme'),
          _field(_tone, 'Tone'),
          _field(_author, 'Author'),
          DropdownButtonFormField<CampaignDifficulty>(
            initialValue: _campaign.difficulty,
            decoration: const InputDecoration(labelText: 'Difficulty'),
            items: CampaignDifficulty.values
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text(value.name)),
                )
                .toList(),
            onChanged: (value) => setState(
              () => _campaign = _campaign.copyWith(difficulty: value),
            ),
          ),
        ];
      case 1:
        return [
          _field(_opening, '开场白', lines: 10),
          _field(_systemPrompt, 'AI GM 系统提示', lines: 10),
        ];
      case 2:
        return [
          _header('章节与剧情节点', _campaign.acts.length),
          ..._campaign.acts.map(
            (act) => ExpansionTile(
              title: Text(act.title),
              subtitle: Text('${act.chapters.length} 章'),
              children: act.chapters
                  .map(
                    (chapter) => ListTile(
                      title: Text(chapter.title),
                      subtitle: Text('${chapter.storyNodes.length} 个节点'),
                    ),
                  )
                  .toList(),
            ),
          ),
          _rawButton(
            '编辑章节 JSON',
            _campaign.acts.map((value) => value.toJson()).toList(),
            (decoded) => _campaign = _campaign.copyWith(
              acts: (decoded as List)
                  .whereType<Map>()
                  .map(
                    (value) =>
                        CampaignAct.fromJson(value.cast<String, Object?>()),
                  )
                  .toList(),
            ),
          ),
        ];
      case 3:
        return [
          _header('地点', _campaign.locations.length),
          ..._campaign.locations.map(
            (value) => ListTile(
              leading: const Icon(Icons.place),
              title: Text(value.name),
              subtitle: Text(value.description),
            ),
          ),
          _rawButton(
            '编辑地点与地图 Marker',
            _campaign.locations.map((value) => value.toJson()).toList(),
            (decoded) => _campaign = _campaign.copyWith(
              locations: (decoded as List)
                  .whereType<Map>()
                  .map(
                    (value) => CampaignLocation.fromJson(
                      value.cast<String, Object?>(),
                    ),
                  )
                  .toList(),
            ),
          ),
        ];
      case 4:
        return [
          _header('NPC 与 AI 队友', _campaign.npcs.length),
          FilledButton.tonalIcon(
            onPressed: _importCharacter,
            icon: const Icon(Icons.person_add_alt),
            label: const Text('从酒馆角色卡导入'),
          ),
          ..._campaign.npcs.map(
            (value) => ListTile(
              leading: CircleAvatar(
                child: Icon(
                  value.role == CampaignNpcRole.companion
                      ? Icons.handshake
                      : Icons.person,
                ),
              ),
              title: Text(value.name),
              subtitle: Text(
                '${value.role.name} · 关系 ${value.relationship} · ${value.personality}',
                maxLines: 2,
              ),
            ),
          ),
          _rawButton(
            '编辑 NPC JSON',
            _campaign.npcs.map((value) => value.toJson()).toList(),
            (decoded) => _campaign = _campaign.copyWith(
              npcs: (decoded as List)
                  .whereType<Map>()
                  .map(
                    (value) =>
                        TRPGNPCProfile.fromJson(value.cast<String, Object?>()),
                  )
                  .toList(),
            ),
          ),
        ];
      case 5:
        return _mapList(
          '任务',
          _campaign.quests,
          (value) => _campaign = _campaign.copyWith(quests: value),
        );
      case 6:
        return [
          _header('线索板数据', _campaign.clues.length),
          ..._campaign.clues.map(
            (value) => ListTile(
              leading: Icon(
                value.visibility == InformationVisibility.public
                    ? Icons.search
                    : Icons.lock_outline,
              ),
              title: Text(value.name),
              subtitle: Text('${value.visibility.name} · ${value.description}'),
            ),
          ),
          _rawButton(
            '编辑线索 JSON',
            _campaign.clues.map((value) => value.toJson()).toList(),
            (decoded) => _campaign = _campaign.copyWith(
              clues: (decoded as List)
                  .whereType<Map>()
                  .map(
                    (value) =>
                        CampaignClue.fromJson(value.cast<String, Object?>()),
                  )
                  .toList(),
            ),
          ),
        ];
      case 7:
        return _mapList(
          '物品',
          _campaign.items,
          (value) => _campaign = _campaign.copyWith(items: value),
        );
      case 8:
        return _mapList(
          '阵营',
          _campaign.factions,
          (value) => _campaign = _campaign.copyWith(factions: value),
        );
      case 9:
        return _mapList(
          '遭遇',
          _campaign.encounters,
          (value) => _campaign = _campaign.copyWith(encounters: value),
        );
      case 10:
        return _stringList(
          'GM Secrets',
          _campaign.secrets,
          (value) => _campaign = _campaign.copyWith(secrets: value),
        );
      case 11:
        return _stringList(
          '可能结局',
          _campaign.endings,
          (value) => _campaign = _campaign.copyWith(endings: value),
        );
      case 12:
        return [
          _header('AI 主持设置', _campaign.aiGmSettings.length),
          const Text(
            '这里保存 GM Prompt、Companion Prompt、参与频率和上下文预算。AI Host Provider 不会因此获得 GM UI 权限。',
          ),
          _rawButton(
            '编辑设置 JSON',
            _campaign.aiGmSettings,
            (decoded) => _campaign = _campaign.copyWith(
              aiGmSettings: (decoded as Map).cast<String, Object?>(),
            ),
          ),
        ];
      default:
        return [
          _header('演出与音频资源', _campaign.audioAssets.length),
          const Text('路径使用 Campaign 相对资源 ID；可配置 BGM、环境音、SFX、默认旁白和转场。'),
          _rawButton(
            '编辑音频资源 JSON',
            _campaign.audioAssets.map((value) => value.toJson()).toList(),
            (decoded) => _campaign = _campaign.copyWith(
              audioAssets: (decoded as List)
                  .whereType<Map>()
                  .map(
                    (value) =>
                        AudioAsset.fromJson(value.cast<String, Object?>()),
                  )
                  .toList(),
            ),
          ),
          _rawButton(
            '编辑演出设置 JSON',
            _campaign.presentationSettings.toJson(),
            (decoded) => _campaign = _campaign.copyWith(
              presentationSettings: CampaignPresentationSettings.fromJson(
                (decoded as Map).cast<String, Object?>(),
              ),
            ),
          ),
          const Divider(),
          const Text(
            '地点的 sceneImage/backgroundId/BGM/Ambient 在“地点”JSON 中配置；NPC 的 portrait/portraitVariants/voice 在“NPC”JSON 中配置。',
          ),
        ];
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      minLines: lines,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget _header(String title, int count) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      '$title（$count）',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
  );
  Widget _rawButton(String label, Object data, void Function(Object) apply) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OutlinedButton.icon(
          onPressed: () => _rawEdit(label, data, apply),
          icon: const Icon(Icons.data_object),
          label: Text(label),
        ),
      );
  List<Widget> _mapList(
    String title,
    List<Map<String, Object?>> values,
    void Function(List<Map<String, Object?>>) apply,
  ) => [
    _header(title, values.length),
    ...values.map(
      (value) => ListTile(
        title: Text(
          (value['title'] ?? value['name'] ?? value['id']).toString(),
        ),
        subtitle: Text(value.toString()),
      ),
    ),
    _rawButton(
      '编辑$title JSON',
      values,
      (decoded) => apply(
        (decoded as List)
            .whereType<Map>()
            .map((value) => value.cast<String, Object?>())
            .toList(),
      ),
    ),
  ];
  List<Widget> _stringList(
    String title,
    List<String> values,
    void Function(List<String>) apply,
  ) => [
    _header(title, values.length),
    ...values.map(
      (value) => ListTile(leading: const Icon(Icons.notes), title: Text(value)),
    ),
    _rawButton(
      '编辑$title JSON',
      values,
      (decoded) =>
          apply((decoded as List).map((value) => value.toString()).toList()),
    ),
  ];
}
