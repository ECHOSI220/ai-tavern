import '../../models/trpg_models.dart';

class CampaignService {
  const CampaignService();

  List<Campaign> get builtInCampaigns => const [
    Campaign(
      id: 'blank_adventure',
      title: '空白冒险',
      description: '由 AI 主持根据角色与玩家行动自然构建的开放冒险。',
      systemPrompt: '保持开放世界，不预设玩家决定。',
      opening: '旅途从一间陌生旅店的雨夜开始。',
      sourceType: CampaignSourceType.template,
    ),
    Campaign(
      id: 'mist_harbor_test',
      title: '雾港疑云',
      description: '适合第一阶段验证的调查型短团。',
      systemPrompt: '这是一场雾港调查冒险。通过环境、NPC 和线索回应玩家行动。',
      opening: '海雾淹没旧港时，一封没有署名的求助信被塞进你的门缝。',
      locations: [
        {'id': 'old_harbor', 'name': '旧港仓库'},
        {'id': 'warehouse_gate', 'name': '仓库铁门'},
        {'id': 'warehouse_interior', 'name': '旧港仓库内部'},
        {'id': 'warehouse_basement', 'name': '潮湿地下室'},
      ],
      npcs: [
        {
          'id': 'guard_hale',
          'name': '守卫哈勒',
          'description': '疲惫而警觉的港区守卫，知道仓库钥匙的下落。',
        },
        {
          'id': 'missing_investigator',
          'name': '调查员伊莱',
          'description': '调查走私航海日志后失踪。',
        },
      ],
      quests: [
        {'id': 'missing_keeper', 'title': '寻找失踪的守灯人'},
      ],
      secrets: ['地下水道藏着被人刻意涂改的航海日志。'],
      items: [
        {'id': 'warehouse_brass_key', 'name': '旧仓库黄铜钥匙', 'category': 'keyItem'},
      ],
      encounters: [
        {'id': 'warehouse_rat_attack', 'name': '地下室鼠群', 'damage': '1D4'},
      ],
      sourceType: CampaignSourceType.template,
    ),
  ];

  Campaign getById(String id) => builtInCampaigns.firstWhere(
    (campaign) => campaign.id == id,
    orElse: () => builtInCampaigns.first,
  );
}
