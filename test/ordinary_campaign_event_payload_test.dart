import 'package:ai_tavern/screens/solo_trpg/solo_session_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary campaign opening scene string does not crash timeline', () {
    const opening = '旅途从一间陌生旅店的雨夜开始。';

    expect(
      trpgEventPayloadLabel(opening, const ['title', 'name', 'id']),
      opening,
    );
  });

  test('tool-generated scene and clue maps still show their labels', () {
    expect(
      trpgEventPayloadLabel(
        const {'id': 'hotel', 'title': '陌生旅店'},
        const ['title', 'name', 'id'],
      ),
      '陌生旅店',
    );
    expect(
      trpgEventPayloadLabel(
        const {'id': 'letter', 'name': '染血的信'},
        const ['name', 'title', 'id'],
      ),
      '染血的信',
    );
  });
}
