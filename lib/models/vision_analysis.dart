class VisionAnalysis {
  const VisionAnalysis({
    this.summary = '',
    this.detailedDescription = '',
    this.detectedText = '',
    this.people = const [],
    this.objects = const [],
    this.scene = '',
    this.mood = '',
    this.composition = '',
    this.safetyNotes = '',
  });

  final String summary;
  final String detailedDescription;
  final String detectedText;
  final List<String> people;
  final List<String> objects;
  final String scene;
  final String mood;
  final String composition;
  final String safetyNotes;

  bool get isEmpty =>
      [
        summary,
        detailedDescription,
        detectedText,
        scene,
        mood,
        composition,
      ].every((item) => item.trim().isEmpty) &&
      people.isEmpty &&
      objects.isEmpty;

  Map<String, Object?> toJson() => {
    'summary': summary,
    'detailedDescription': detailedDescription,
    'detectedText': detectedText,
    'people': people,
    'objects': objects,
    'scene': scene,
    'mood': mood,
    'composition': composition,
    'safetyNotes': safetyNotes,
  };

  factory VisionAnalysis.fromJson(Map<String, Object?> json) => VisionAnalysis(
    summary: _text(json['summary']),
    detailedDescription: _text(
      json['detailedDescription'] ?? json['detailed_description'],
    ),
    detectedText: _text(json['detectedText'] ?? json['detected_text']),
    people: _strings(json['people']),
    objects: _strings(json['objects']),
    scene: _text(json['scene']),
    mood: _text(json['mood']),
    composition: _text(json['composition']),
    safetyNotes: _text(json['safetyNotes'] ?? json['safety_notes']),
  );

  static String _text(Object? value) => value?.toString().trim() ?? '';

  static List<String> _strings(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    final text = _text(value);
    return text.isEmpty ? const [] : [text];
  }
}
