enum AppMode { tavern, soloTrpg, multiplayerTrpg, characterSocial }

extension AppModeLabel on AppMode {
  String get label => switch (this) {
    AppMode.tavern => 'AI 酒馆',
    AppMode.characterSocial => '角色社交',
    AppMode.soloTrpg => '单人跑团',
    AppMode.multiplayerTrpg => '多人跑团',
  };

  String get subtitle => switch (this) {
    AppMode.tavern => '角色聊天',
    AppMode.characterSocial => '消息 · 联系人 · 朋友圈',
    AppMode.soloTrpg => 'AI 主持 · 单人冒险',
    AppMode.multiplayerTrpg => '多人联机 · AI 主持',
  };
}
