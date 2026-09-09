import 'package:ai_tavern/widgets/community_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  testWidgets(
    'community buttons open the correct external browser pages on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CommunityLinks())),
      );
      await tester.tap(find.text('打开网页社区'));
      await tester.pumpAndSettle();
      expect(
        calls.last.arguments['url'],
        'https://ai-tavern-cloud.pages.dev/discover',
      );
      expect(calls.last.arguments['useWebView'], false);
      await tester.tap(find.text('网页我的创作'));
      await tester.pumpAndSettle();
      expect(
        calls.last.arguments['url'],
        'https://ai-tavern-cloud.pages.dev/me/uploads',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed browser launch offers a copyable link', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CommunityLinks())),
    );
    await tester.tap(find.text('打开网页社区'));
    await tester.pumpAndSettle();
    expect(find.text('请在浏览器中打开'), findsOneWidget);
    expect(find.text('复制网址'), findsOneWidget);
  });
}
