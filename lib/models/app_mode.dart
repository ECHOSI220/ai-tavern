enum AppMode { tavern, soloTrpg, multiplayerTrpg }

extension AppModeLabel on AppMode {
  String get label => switch (this) {
    AppMode.tavern => 'AI 酒馆',
    AppMode.soloTrpg => '单人跑团',
    AppMode.multiplayerTrpg => '多人跑团',
  };

  String get subtitle => switch (this) {
    AppMode.tavern => '角色聊天',
    AppMode.soloTrpg => 'AI 主持 · 单人冒险',
    AppMode.multiplayerTrpg => '多人联机 · AI 主持',
  };
}
