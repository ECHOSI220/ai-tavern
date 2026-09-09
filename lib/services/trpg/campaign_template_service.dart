import '../../models/campaign_models.dart';
import '../../models/trpg_models.dart';
import '../../models/trpg_presentation_models.dart';
import 'campaign_service.dart';

class CampaignTemplateService {
  const CampaignTemplateService();

  List<CampaignDocument> get templates => [
    holyGrailWar(),
    _simple('mystery_template', '悬疑调查', '调查、证词与线索链', '悬疑', '严肃'),
    _simple('dungeon_template', '地牢冒险', '探索区域、遭遇与宝藏', '奇幻', '冒险'),
    _simple('urban_legend_template', '都市怪谈', '现代都市中的异常事件', '现代都市', '诡异'),
    _simple('survival_template', '生存逃脱', '资源管理与路线选择', '生存', '紧张'),
    _simple('sandbox_template', '自由沙盒', '开放地点与阵营驱动', '沙盒', '开放'),
  ];

  CampaignDocument holyGrailWar() {
    final now = DateTime.now();
    return CampaignDocument(
      id: 'holy_grail_war_fuyuki_echo',
      campaignType: CampaignType.holyGrailWar,
      title: '第七次圣杯战争：冬木残响',
      description:
          '在 TYPE-MOON《Fate》共通底层规则上建立的全新平行分支圣杯战争。七名御主与七骑从者的情报、关系、联盟、背叛与愿望共同决定结局，不复述任何已有作品路线。',
      tags: const ['Fate世界观', '圣杯战争', '平行分支', '都市奇幻', '阵营博弈', '动态剧本'],
      recommendedPlayers: '1~7',
      estimatedLength: '12~40小时',
      ruleSystem: 'Holy Grail War TRPG',
      theme: '现代都市魔术战争',
      tone: '严肃、悬疑、英雄史诗',
      difficulty: CampaignDifficulty.hard,
      author: '幻境酒馆',
      source: CampaignSourceType.template,
      createdAt: now,
      updatedAt: now,
      opening: '冬木市的七处灵脉在同一夜发出脉动。你的手背浮现出三道令咒，而召唤阵中的银光正逐渐凝成人形。你必须先决定自己为何而战。',
      systemPrompt: '''
你正在主持一场位于 TYPE-MOON《Fate》宏大世界观下、但发生在全新平行分支的圣杯战争 TRPG。
世界书中来自 Fate/Zero、Fate/stay night、Fate/Grand Order、君主·埃尔梅罗二世事件簿、Fate/Apocrypha、Fate/strange Fake与 Fate/Prototype 苍银的碎片的概念，只用于共通规则、机构与平行案例参照，不得将彼此冲突的事件强行当成同一条时间线的既定历史。
这是“新的圣杯战争”：可借用英灵座、职阶容器、令咒、灵脉、魔术协会、圣堂教会、亚种/伪圣杯战争等底层设定，但御主、阴谋、异常核心、胜负与结局必须由当前 Campaign 独立生成。
不要复述固定小说、动画或游戏剧情；已有人物与事件不会自动存在，只能在当前剧本明确引入后使用。
每个御主拥有自己的目标；每个从者拥有独立人格、记忆、感情和判断，可以拒绝不合理命令。
隐藏其他阵营的位置、计划、御主身份、从者真名、传说与宝具真名，只有调查、目击或主动暴露后才能公开。
战斗结果必须综合能力参数、情报、策略、关系、令咒、环境与资源。允许追踪、保护或暗杀御主。
剧情由 NPC Goal、Faction Goal、Quest、玩家选择及 GM Director 动态推动。不要强制还原任何既有故事路线。
''',
      acts: const [
        CampaignAct(
          id: 'hgw_act_1',
          title: '第一阶段：召唤之夜',
          chapters: [
            CampaignChapter(
              id: 'hgw_chapter_summoning',
              title: '令咒与召唤阵',
              storyNodes: [
                StoryNode(
                  id: 'hgw_choose_master',
                  title: '御主的愿望',
                  description: '确定御主身份、愿望、魔术属性和媒介。',
                  nextNodes: ['hgw_summon_servant'],
                ),
                StoryNode(
                  id: 'hgw_summon_servant',
                  title: '英灵回应',
                  prerequisites: ['hgw_choose_master'],
                  description: '召唤系统根据御主愿望、性格、媒介和魔术属性匹配从者。',
                ),
              ],
            ),
          ],
        ),
        CampaignAct(
          id: 'hgw_act_2',
          title: '第二阶段：初次交战',
          chapters: [
            CampaignChapter(
              id: 'hgw_chapter_first_blood',
              title: '第一次目击',
              storyNodes: [
                StoryNode(
                  id: 'hgw_first_contact',
                  title: '灵体交锋',
                  description: '通过观察和试探建立第一批职阶情报。',
                ),
              ],
            ),
          ],
        ),
        CampaignAct(
          id: 'hgw_act_3',
          title: '第三阶段：联盟与猎杀',
          chapters: [
            CampaignChapter(
              id: 'hgw_chapter_alliance',
              title: '不稳定的盟约',
              storyNodes: [
                StoryNode(
                  id: 'hgw_hunt',
                  title: '共同的强敌',
                  description: '阵营基于利益形成临时联盟，也可能背叛。',
                ),
              ],
            ),
          ],
        ),
        CampaignAct(
          id: 'hgw_act_4',
          title: '第四阶段：真相调查',
          chapters: [
            CampaignChapter(
              id: 'hgw_chapter_truth',
              title: '被污染的灵脉',
              storyNodes: [
                StoryNode(
                  id: 'hgw_anomaly',
                  title: '圣杯异常',
                  description: '幸存者逐渐发现仪式背后的异常。',
                ),
              ],
            ),
          ],
        ),
        CampaignAct(
          id: 'hgw_act_5',
          title: '第五阶段：最终决战',
          chapters: [
            CampaignChapter(
              id: 'hgw_chapter_final',
              title: '大圣杯之前',
              storyNodes: [
                StoryNode(
                  id: 'hgw_final_choice',
                  title: '愿望的代价',
                  description: '幸存阵营必须决定赢取、摧毁或改变圣杯。',
                ),
              ],
            ),
          ],
        ),
      ],
      locations: const [
        CampaignLocation(
          id: 'fuyuki_city',
          name: '冬木市',
          description: '灵脉交错的沿海城市，战争在日常表象之下进行。',
          discovered: true,
        ),
        CampaignLocation(
          id: 'miyama_town',
          name: '深山町',
          description: '古老家系宅邸和寺院所在的旧城区。',
          discovered: true,
        ),
        CampaignLocation(
          id: 'shinto_district',
          name: '新都',
          description: '高楼、商场与夜间人流密集的新城区。',
          discovered: true,
        ),
        CampaignLocation(
          id: 'ryuudou_temple',
          name: '柳洞寺',
          description: '位于灵脉节点上的古寺。',
        ),
        CampaignLocation(
          id: 'fuyuki_church',
          name: '冬木教会',
          description: '战争监督者所在的中立地带。',
          discovered: true,
        ),
        CampaignLocation(
          id: 'greater_grail',
          name: '大圣杯地窟',
          description: '仪式核心，正常情况下无人知道入口。',
          hidden: true,
        ),
      ],
      npcs: const [
        TRPGNPCProfile(
          npcId: 'hgw_overseer',
          name: '监督者·言峰礼司',
          description: '负责记录退场阵营并维持表面秩序的教会监督者。',
          personality: '冷静、礼貌、从不提供免费的完整答案。',
          role: CampaignNpcRole.majorNpc,
          faction: 'holy_church',
          locationId: 'fuyuki_church',
          knownToPlayers: true,
          privateNotes: '知道仪式存在异常，但在确认污染源之前保持观望。',
          metadata: {
            'goal': '维持战争规则，并查明灵脉异常来源。',
            'values': ['秩序', '契约'],
            'knownLocationIds': ['fuyuki_church'],
          },
        ),
        TRPGNPCProfile(
          npcId: 'association_observer',
          name: '魔术协会观察员',
          description: '来自时钟塔的非正式观察员。',
          personality: '傲慢、敏锐、重视稀有魔术资料。',
          role: CampaignNpcRole.majorNpc,
          faction: 'mage_association',
          locationId: 'shinto_district',
          privateNotes: '优先回收异常圣杯资料，而非保护参战者。',
          metadata: {'goal': '采集圣杯异常数据并安全带回协会。'},
        ),
      ],
      quests: const [
        {'id': 'hgw_summon', 'title': '完成从者召唤', 'phase': 'PHASE1'},
        {'id': 'hgw_first_intel', 'title': '确认至少一个敌方职阶', 'phase': 'PHASE2'},
        {'id': 'hgw_trace_master', 'title': '找出一名敌方御主', 'phase': 'PHASE2'},
        {'id': 'hgw_choose_alliance', 'title': '决定是否缔结临时联盟', 'phase': 'PHASE3'},
        {'id': 'hgw_grail_truth', 'title': '调查圣杯异常', 'phase': 'PHASE4'},
        {'id': 'hgw_final_wish', 'title': '面对愿望的代价', 'phase': 'PHASE5'},
      ],
      clues: const [
        CampaignClue(
          id: 'hgw_mana_trace',
          name: '残留魔力轨迹',
          description: '可用于判断从者的行动方向和部分能力特征。',
        ),
        CampaignClue(
          id: 'hgw_command_mark',
          name: '令咒目击记录',
          description: '可能将普通市民与御主区分开。',
          visibility: InformationVisibility.playerPrivate,
        ),
        CampaignClue(
          id: 'hgw_grail_mud',
          name: '黑色魔力残渣',
          description: '与正常灵脉性质不同，指向圣杯异常。',
          visibility: InformationVisibility.gmOnly,
        ),
      ],
      factions: const [
        {
          'id': 'holy_church',
          'name': '圣堂教会',
          'goal': '监督战争并控制异常扩散',
          'resources': 70,
          'influence': 75,
        },
        {
          'id': 'mage_association',
          'name': '魔术协会',
          'goal': '研究并回收圣杯术式',
          'resources': 85,
          'influence': 80,
        },
        {
          'id': 'three_families',
          'name': '御三家旧盟',
          'goal': '夺回对大圣杯仪式的主导权',
          'resources': 80,
          'influence': 70,
        },
      ],
      encounters: const [
        {
          'id': 'hgw_scouting_clash',
          'title': '夜间试探',
          'phase': 'PHASE2',
          'dynamic': true,
        },
        {
          'id': 'hgw_master_ambush',
          'title': '御主伏击',
          'phase': 'PHASE3',
          'dynamic': true,
        },
        {
          'id': 'hgw_grail_guardian',
          'title': '异常守护者',
          'phase': 'PHASE4',
          'dynamic': true,
        },
      ],
      secrets: const [
        '大圣杯并非完全纯净，异常程度会随不受控制的愿望与退场灵魂上升。',
        '监督者并非全知，他掌握规则但也需要玩家提供证据。',
        '隐藏真结局需要至少一项跨阵营信任、三条异常线索以及拒绝直接许愿。',
      ],
      endings: const ['胜利并获得圣杯', '主动毁灭圣杯', '圣杯污染失控', '成为新任监督者', '揭开仪式真相的隐藏结局'],
      aiGmSettings: const {
        'dynamicEvents': true,
        'hideTrueNames': true,
        'allowMasterAssassination': true,
        'allowBetrayal': true,
        'maxTeams': 7,
      },
      metadata: const {
        'campaignType': 'HOLY_GRAIL_WAR',
        'holyGrailTemplateVersion': 2,
        'requiredManager': 'HolyGrailWarManager',
        'fateUniverseMode': 'parallel_branch_original_holy_grail_war',
        'linkedWorldBookId': 'type_moon_fate_shared_world_v1',
        'fateWorldBook': [
          {
            'id': 'fate_parallel_world_rule',
            'title': '平行世界与本战役边界',
            'keywords': ['平行世界', '时间线', '分支', '剧情边界'],
            'content':
                '本剧本是 Fate 共通概念下的原创平行分支。Fate/Zero、Fate/stay night、FGO、Apocrypha、strange Fake、苍银与事件簿的事件属于可参照的不同记录，不默认同时发生。本战争的玩家、敌对御主、阴谋和结局都是新的。',
          },
          {
            'id': 'fate_magecraft_root',
            'title': '魔术、神秘与根源',
            'keywords': ['魔术', '神秘', '根源', '魔术回路', '起源'],
            'content':
                '魔术师以魔术回路、家系刻印、基盘与神秘行使现代术式，许多家系的终极目标是抵达根源。起源和属性影响个人的魔术倾向，但不等于人格的全部。神秘一般需要避免向普通社会暴露。',
          },
          {
            'id': 'fate_mage_association',
            'title': '魔术协会与时钟塔',
            'keywords': ['魔术协会', '时钟塔', '君主', '封印指定'],
            'content':
                '魔术协会是管理、研究与保全魔术的大型组织；伦敦时钟塔是其重要中心与学术政治舞台。派阀、学科、君主、封印指定和稀有神秘会让观察员的目标不必与参战者安全一致。',
          },
          {
            'id': 'fate_holy_church',
            'title': '圣堂教会与监督',
            'keywords': ['圣堂教会', '监督者', '中立地带', '异端'],
            'content':
                '圣堂教会处理异端与不应流入人类社会的神秘。圣杯战争的监督者负责登记、见证规则与接纳失去从者的御主，但监督者并非必然公正、全知或无法被渗透。',
          },
          {
            'id': 'fate_throne_heroic_spirits',
            'title': '英灵座、英灵与从者',
            'keywords': ['英灵座', '英灵', '从者', '传说', '知名度'],
            'content':
                '被人类史、神话或传说记录的英雄以更高位的英灵形态存在；圣杯通过职阶容器召唤的是适合当前仪式的从者侧面。从者有自己的愿望、价值观与判断，不是只会执行命令的道具。',
          },
          {
            'id': 'fate_seven_classes',
            'title': '七职阶容器与宝具',
            'keywords': [
              'Saber',
              'Archer',
              'Lancer',
              'Rider',
              'Caster',
              'Assassin',
              'Berserker',
              '宝具',
            ],
            'content':
                '标准仪式使用 Saber、Archer、Lancer、Rider、Caster、Assassin、Berserker 七个职阶容器。职阶赋予技能与限制，从者本身另有传说形成的宝具。真名、宝具效果与弱点都是战略情报。',
          },
          {
            'id': 'fate_master_command_spells',
            'title': '御主、契约与令咒',
            'keywords': ['御主', '契约', '令咒', '魔力供给'],
            'content':
                '御主向从者提供现界锚点与魔力。三划令咒可用于绝对命令、跨距离召回或短时强化，每次使用都是不可轻易恢复的战略资源，强制命令也会伤害主从关系。',
          },
          {
            'id': 'fate_fuyuki_ritual',
            'title': '冬木式圣杯仪式',
            'keywords': ['冬木', '大圣杯', '小圣杯', '御三家', '灵脉'],
            'content':
                '冬木式仪式以地下灵脉和大规模术式为基础，利用从者退场后的魔力推进圣杯降临。御三家对仪式各有历史责任与私心。本战役沿用类似底层架构，但“冬木残响”的异常来源是新谜题。',
          },
          {
            'id': 'fate_variant_wars',
            'title': '亚种、大圣杯与伪圣杯战争',
            'keywords': ['Apocrypha', 'strange Fake', '亚种圣杯战争', '大圣杯战争', '伪圣杯'],
            'content':
                '历史上可能出现仿制、扩容或歪曲的圣杯系统：例如阵营对抗的大圣杯战争，或职阶缺失、召唤异常的伪圣杯战争。这些案例证明仪式不必永远严格复制冬木，但异常必须有可调查的术式原因。',
          },
          {
            'id': 'fate_tokyo_prototype_case',
            'title': '东京圣杯战争平行案例',
            'keywords': ['Prototype', '苍银的碎片', '东京圣杯战争'],
            'content':
                '另一平行系统中也存在七名魔术师与七骑英灵围绕愿望机的东京圣杯战争。可用来提醒 GM：城市地理、召唤顺序、圣杯性质和阴谋都可不同，不应把冬木战争当成唯一模板。',
          },
          {
            'id': 'fate_grand_order_scope',
            'title': '人理、特异点与冠位指定',
            'keywords': ['FGO', '人理', '特异点', '冠位指定', '迦勒底'],
            'content':
                '某些平行记录中，魔术与科学被同时用于观测人类史，英灵召唤也可服务于修复特异点的“冠位指定”。本战役不默认迦勒底介入；只在剧情真正涉及人理级异常时，才能把它作为遥远背景或后期钩子。',
          },
          {
            'id': 'fate_information_warfare',
            'title': '神秘隐蔽与情报战',
            'keywords': ['情报', '真名', '神秘隐蔽', '目击者', '灵体化'],
            'content':
                '圣杯战争不是公开竞技。真名会暴露传说中的弱点，魔力轨迹、工房、使魔、目击记录、令咒和宝具现象都能形成情报链。普通人目击异常后应产生现实后果，组织会尝试收容、消除或伪装事件。',
          },
          {
            'id': 'fate_gm_canon_priority',
            'title': '主持裁定的设定优先级',
            'keywords': ['设定优先级', '世界一致性', '裁定'],
            'content':
                '当资料互相冲突时，优先级为：当前 Campaign 明确真相 > 已保存的结构化世界状态 > 本世界书共通规则 > 其他作品的平行案例。AI 不得为了还原原作而覆盖玩家已经造成的世界变化。',
          },
        ],
        'officialLoreSources': [
          {
            'title': 'Fate/stay night 官方用语集',
            'url': 'https://www.fate-sn.com/sp/story-chara/glossary.html',
          },
          {
            'title': 'Fate/stay night [UBW] 官方导语',
            'url': 'https://www.fate-sn.com/ubw/intro/',
          },
          {
            'title': 'Fate/Zero 官方介绍',
            'url': 'https://www.fate-zero.jp/introduction/',
          },
          {
            'title': 'Fate/Apocrypha 官方故事',
            'url': 'https://fate-apocrypha.com/sp/story/?no=1',
          },
          {
            'title': 'Fate/strange Fake 官方世界',
            'url': 'https://fatesf-anime.com/world/',
          },
          {
            'title': 'Fate/Grand Order 官方世界',
            'url': 'https://static.fate-go.jp/world/1st/',
          },
          {
            'title': 'Fate/Prototype 苍银的碎片官方页',
            'url': 'https://www.aniplex.co.jp/lineup/fate-pt-sougin/',
          },
          {
            'title': '君主·埃尔梅罗二世事件簿官方资料',
            'url': 'https://anime.elmelloi.com/pdf/vol2.pdf',
          },
        ],
      },
    );
  }

  CampaignDocument mistHarbor() {
    final legacy = const CampaignService().getById('mist_harbor_test');
    final base = CampaignDocument.fromLegacy(legacy);
    return base.copyWith(
      title: '雾港疑云',
      description: '适合 1~4 人的调查短团。失踪调查员、旧仓库与被篡改的航海日志彼此相连。',
      tags: const ['悬疑', '调查', '现代奇谭'],
      recommendedPlayers: '1~4',
      estimatedLength: '2~4小时',
      ruleSystem: '通用规则',
      theme: '雾港调查',
      tone: '严肃 + 少量幽默',
      author: '幻境酒馆',
      source: CampaignSourceType.template,
      acts: const [
        CampaignAct(
          id: 'act_arrival',
          title: '第一幕：雾中来信',
          chapters: [
            CampaignChapter(
              id: 'chapter_harbor',
              title: '旧港调查',
              storyNodes: [
                StoryNode(
                  id: 'node_letter',
                  title: '无名求助信',
                  description: '玩家收到指向旧仓库的求助信。',
                  nextNodes: ['node_gate'],
                ),
                StoryNode(
                  id: 'node_gate',
                  title: '仓库铁门',
                  prerequisites: ['node_letter'],
                  description: '守卫哈勒掌握黄铜钥匙的线索。',
                  nextNodes: ['node_basement'],
                ),
                StoryNode(
                  id: 'node_basement',
                  title: '潮湿地下室',
                  prerequisites: ['node_gate'],
                  description: '被篡改的日志揭示真正航线。',
                ),
              ],
            ),
          ],
        ),
      ],
      locations: const [
        CampaignLocation(
          id: 'old_harbor',
          name: '旧港',
          description: '终年被海雾笼罩的老码头。',
          discovered: true,
          backgroundId: 'mist_harbor_port',
          visualTheme: CampaignVisualTheme.horror,
          timeOfDay: '夜晚',
          weather: '雨',
          ambientId: 'rain',
          bgmId: 'exploration',
        ),
        CampaignLocation(
          id: 'warehouse_gate',
          name: '仓库铁门',
          description: '生锈铁门旁留有新近脚印。',
          backgroundId: 'mist_harbor_warehouse_gate',
          ambientId: 'rain',
          bgmId: 'mystery',
        ),
        CampaignLocation(
          id: 'warehouse_interior',
          name: '旧仓库内部',
          description: '木箱与盐味掩盖了某种药剂气味。',
          backgroundId: 'mist_harbor_warehouse',
          ambientId: 'warehouse',
          bgmId: 'mystery',
        ),
        CampaignLocation(
          id: 'warehouse_basement',
          name: '潮湿地下室',
          description: '隐蔽排水道通向海湾。',
          hidden: true,
          backgroundId: 'mist_harbor_underground_altar',
          ambientId: 'underground',
          bgmId: 'danger',
        ),
      ],
      npcs: const [
        TRPGNPCProfile(
          npcId: 'guard_hale',
          name: '守卫哈勒',
          description: '疲惫而警觉的港区守卫。',
          locationId: 'warehouse_gate',
          knownToPlayers: true,
          portraitVariants: {'neutral': '', 'angry': '', 'fear': ''},
        ),
        TRPGNPCProfile(
          npcId: 'missing_investigator',
          name: '调查员伊莱',
          description: '追查失踪航海日志后失踪。',
          locationId: 'warehouse_basement',
          role: CampaignNpcRole.majorNpc,
          portraitVariants: {'neutral': '', 'injured': ''},
        ),
        TRPGNPCProfile(
          npcId: 'dock_boss',
          name: '港口老板莫里斯',
          description: '待人热络，却不断转移话题。',
          locationId: 'old_harbor',
          role: CampaignNpcRole.enemy,
          privateNotes: '他是走私与失踪案的主谋。',
          portraitVariants: {'neutral': '', 'angry': '', 'surprised': ''},
        ),
        TRPGNPCProfile(
          npcId: 'companion_lyra',
          name: '莉拉',
          description: '熟悉港区小路的年轻向导。',
          personality: '谨慎、敏锐，不会盲从玩家。',
          role: CampaignNpcRole.companion,
          locationId: 'old_harbor',
          knownToPlayers: true,
          portraitVariants: {
            'neutral': '',
            'happy': '',
            'thinking': '',
            'fear': '',
          },
        ),
      ],
      quests: const [
        {
          'id': 'find_investigator',
          'title': '寻找失踪调查员',
          'locationId': 'warehouse_basement',
        },
        {
          'id': 'open_warehouse',
          'title': '进入旧仓库',
          'requiredClueIds': ['warehouse_key'],
        },
        {
          'id': 'expose_smuggling',
          'title': '揭露走私网络',
          'requiredClueIds': ['altered_log', 'blood_trace'],
        },
      ],
      clues: const [
        CampaignClue(
          id: 'anonymous_letter',
          name: '无名求助信',
          description: '信纸带有港务处水印。',
          discovered: true,
        ),
        CampaignClue(
          id: 'warehouse_key',
          name: '仓库黄铜钥匙',
          description: '可能打开旧仓库侧门。',
          source: '守卫哈勒',
        ),
        CampaignClue(
          id: 'fresh_footprints',
          name: '新鲜脚印',
          description: '脚印通向仓库侧门。',
        ),
        CampaignClue(
          id: 'altered_log',
          name: '被篡改的航海日志',
          description: '删除的航线指向北湾。',
        ),
        CampaignClue(
          id: 'blood_trace',
          name: '干涸血迹',
          description: '血迹延伸到地下室。',
          visibility: InformationVisibility.playerPrivate,
        ),
        CampaignClue(
          id: 'medicine_smell',
          name: '药剂气味',
          description: '来自被伪装的木箱。',
        ),
        CampaignClue(id: 'torn_badge', name: '撕裂的调查员徽章', description: '属于伊莱。'),
        CampaignClue(
          id: 'tide_schedule',
          name: '异常潮汐表',
          description: '标记了秘密运输窗口。',
        ),
      ],
      secrets: const ['港口老板莫里斯是走私首脑。', '地下水道的出口只在退潮后一小时可通行。'],
      endings: const ['救出伊莱并公开证据', '走私网络逃脱但玩家保住证人', '港口在冲突中被封锁'],
      audioAssets: const [
        AudioAsset(
          id: 'exploration',
          type: AudioAssetType.bgm,
          path: '',
          tags: ['exploration', 'calm'],
        ),
        AudioAsset(
          id: 'mystery',
          type: AudioAssetType.bgm,
          path: '',
          tags: ['mystery', 'danger'],
        ),
        AudioAsset(
          id: 'battle',
          type: AudioAssetType.bgm,
          path: '',
          tags: ['battle', 'boss'],
        ),
        AudioAsset(
          id: 'rain',
          type: AudioAssetType.ambient,
          path: '',
          tags: ['rain', 'sea'],
        ),
        AudioAsset(
          id: 'warehouse',
          type: AudioAssetType.ambient,
          path: '',
          tags: ['warehouse', 'wind'],
        ),
        AudioAsset(
          id: 'underground',
          type: AudioAssetType.ambient,
          path: '',
          tags: ['underground', 'machine'],
        ),
      ],
      presentationSettings: const CampaignPresentationSettings(
        defaultBgm: 'exploration',
        defaultAmbient: 'rain',
        transitionStyle: SceneTransitionStyle.crossfade,
        uiTheme: CampaignVisualTheme.horror,
      ),
    );
  }

  CampaignDocument _simple(
    String id,
    String title,
    String description,
    String theme,
    String tone,
  ) {
    final now = DateTime.now();
    return CampaignDocument(
      id: id,
      title: title,
      description: description,
      tags: [theme, tone],
      theme: theme,
      tone: tone,
      source: CampaignSourceType.template,
      createdAt: now,
      updatedAt: now,
      acts: const [CampaignAct(id: 'act_1', title: '第一幕', chapters: [])],
    );
  }
}
