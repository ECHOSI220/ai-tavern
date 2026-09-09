enum CardBuildTarget {
  story,
  character;

  String get label => switch (this) {
    CardBuildTarget.story => '剧情卡',
    CardBuildTarget.character => '角色卡',
  };

  String get description => switch (this) {
    CardBuildTarget.story => '生成角色、世界观、世界书、开场剧情与玩法设置',
    CardBuildTarget.character => '生成单个角色的完整人设、背景、关系与对话示例',
  };
}
