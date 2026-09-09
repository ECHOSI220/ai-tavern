enum PlayMode {
  freeform,
  choice;

  String get label => switch (this) {
    PlayMode.freeform => '普通玩法',
    PlayMode.choice => '选项玩法',
  };

  static PlayMode fromJson(Object? value) => switch (value) {
    'choice' => PlayMode.choice,
    _ => PlayMode.freeform,
  };
}
