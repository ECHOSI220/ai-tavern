enum PlayerReplyTone {
  natural('自然', '自然、符合当前身份和情境，不刻意夸张'),
  happy('开心', '明快、积极、带有愉悦和期待'),
  angry('生气', '明显不满、有火气，但仍符合角色身份'),
  decisive('果断', '直接明确、迅速表态，不拖泥带水'),
  gentle('温柔', '体贴、柔和，注意对方感受'),
  calm('冷静', '理性克制，先观察和分析再表达'),
  humorous('幽默', '轻松风趣，用恰当玩笑缓和气氛'),
  cautious('谨慎', '保留余地、试探信息、避免过早暴露意图'),
  brave('勇敢', '迎难而上，表现坚定和担当'),
  shy('害羞', '拘谨含蓄，略有迟疑但仍能表达核心意思'),
  tsundere('傲娇', '嘴硬心软，表面不在意但暗含真实关心'),
  suspicious('怀疑', '保持警觉，质疑细节并要求更多证据'),
  sad('悲伤', '低落克制，流露失望、痛苦或怀念'),
  nervous('紧张', '不安、急促、略带犹豫，体现当前压力'),
  sincere('真诚', '坦率诚恳，不绕弯，重视真实感受'),
  forceful('强势', '有压迫感和主导性，清楚提出要求或底线'),
  cunning('狡黠', '机敏、带试探和小心思，保留真正目的'),
  romantic('浪漫', '富有情感与氛围感，表达欣赏、依恋或心动'),
  indifferent('冷淡', '疏离简短，控制情绪并保持距离'),
  diplomatic('委婉', '措辞圆润、照顾关系，用间接方式表达立场');

  const PlayerReplyTone(this.label, this.instruction);

  final String label;
  final String instruction;
}

class PlayerReplyToneSelection {
  const PlayerReplyToneSelection({required this.tone, this.customTone = ''});

  final PlayerReplyTone tone;
  final String customTone;
}
