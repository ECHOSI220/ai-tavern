class Character {
  const Character({
    required this.id,
    required this.name,
    this.avatar,
    this.description = '',
    this.personality = '',
    this.appearance = '',
    this.background = '',
    this.speakingStyle = '',
    this.relationship = '',
    this.goals = '',
    this.secrets = '',
    this.exampleDialogue = '',
    this.scenarioNotes = '',
    this.enabled = true,
    this.socialProfile = const {},
  });

  final String id;
  final String name;
  final String? avatar;
  final String description;
  final String personality;
  final String appearance;
  final String background;
  final String speakingStyle;
  final String relationship;
  final String goals;
  final String secrets;
  final String exampleDialogue;
  final String scenarioNotes;
  final bool enabled;

  /// Optional behavior extension; never a second copy of the character persona.
  final Map<String, Object?> socialProfile;

  Character copyWith({
    String? id,
    String? name,
    String? avatar,
    bool clearAvatar = false,
    String? description,
    String? personality,
    String? appearance,
    String? background,
    String? speakingStyle,
    String? relationship,
    String? goals,
    String? secrets,
    String? exampleDialogue,
    String? scenarioNotes,
    bool? enabled,
    Map<String, Object?>? socialProfile,
  }) => Character(
    id: id ?? this.id,
    name: name ?? this.name,
    avatar: clearAvatar ? null : avatar ?? this.avatar,
    description: description ?? this.description,
    personality: personality ?? this.personality,
    appearance: appearance ?? this.appearance,
    background: background ?? this.background,
    speakingStyle: speakingStyle ?? this.speakingStyle,
    relationship: relationship ?? this.relationship,
    goals: goals ?? this.goals,
    secrets: secrets ?? this.secrets,
    exampleDialogue: exampleDialogue ?? this.exampleDialogue,
    scenarioNotes: scenarioNotes ?? this.scenarioNotes,
    enabled: enabled ?? this.enabled,
    socialProfile: socialProfile ?? this.socialProfile,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'description': description,
    'personality': personality,
    'appearance': appearance,
    'background': background,
    'speakingStyle': speakingStyle,
    'relationship': relationship,
    'goals': goals,
    'secrets': secrets,
    'exampleDialogue': exampleDialogue,
    'scenarioNotes': scenarioNotes,
    'enabled': enabled,
    'socialProfile': socialProfile,
  };

  factory Character.fromJson(Map<String, Object?> json) => Character(
    id: json['id']! as String,
    name: json['name']! as String,
    avatar: json['avatar'] as String?,
    description: json['description'] as String? ?? '',
    personality: json['personality'] as String? ?? '',
    appearance: json['appearance'] as String? ?? '',
    background: json['background'] as String? ?? '',
    speakingStyle: json['speakingStyle'] as String? ?? '',
    relationship: json['relationship'] as String? ?? '',
    goals: json['goals'] as String? ?? '',
    secrets: json['secrets'] as String? ?? '',
    exampleDialogue: json['exampleDialogue'] as String? ?? '',
    scenarioNotes: json['scenarioNotes'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
    socialProfile: json['socialProfile'] is Map
        ? (json['socialProfile'] as Map).cast<String, Object?>()
        : const {},
  );
}
