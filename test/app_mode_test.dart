import 'package:ai_tavern/models/app_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unified home mode contract exposes all four entries', () {
    expect(AppMode.values, hasLength(4));
    expect(
      AppMode.values.map((mode) => mode.label),
      containsAll(<String>['AI 酒馆', '单人跑团', '多人跑团', '角色社交']),
    );
    expect(AppMode.tavern.subtitle, '角色聊天');
    expect(AppMode.soloTrpg.subtitle, contains('AI 主持'));
    expect(AppMode.multiplayerTrpg.subtitle, contains('多人联机'));
  });
}
