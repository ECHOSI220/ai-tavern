import 'package:ai_tavern/models/trpg_models.dart';
import 'package:ai_tavern/screens/trpg_shared/trpg_private_mailbox_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('私信会话按最新消息排序且聊天页新消息位于旧消息下方', (tester) async {
    final oldTime = DateTime.utc(2026, 9, 6, 10);
    final newTime = DateTime.utc(2026, 9, 6, 11);
    final messages = [
      TRPGPrivateMessage(
        id: 'old',
        senderId: 'friend-old',
        recipientIds: const ['human', 'friend-old'],
        content: '较早的会话',
        createdAt: oldTime,
      ),
      TRPGPrivateMessage(
        id: 'new-1',
        senderId: 'human',
        recipientIds: const ['human', 'friend-new'],
        content: '旧消息在上方',
        createdAt: oldTime,
      ),
      TRPGPrivateMessage(
        id: 'new-2',
        senderId: 'friend-new',
        recipientIds: const ['human', 'friend-new'],
        content: '最新消息在下方',
        createdAt: newTime,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: TrpgPrivateMailboxScreen(
          currentPlayerId: 'human',
          contacts: const [
            TrpgPrivateContact(id: 'friend-old', name: '旧联系人'),
            TrpgPrivateContact(id: 'friend-new', name: '新联系人'),
          ],
          messages: messages,
          resolveName: (id) => id,
          onSend: (_, _) async => messages,
          initialUnreadContactIds: const {'friend-new'},
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('新联系人')).dy,
      lessThan(tester.getTopLeft(find.text('旧联系人')).dy),
    );

    await tester.tap(find.text('新联系人'));
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('旧消息在上方')).dy,
      lessThan(tester.getTopLeft(find.text('最新消息在下方')).dy),
    );
  });

  testWidgets('私信发送后的乐观消息不会被延迟空快照清掉', (tester) async {
    final updates = ValueNotifier<List<TRPGPrivateMessage>>(const []);
    addTearDown(updates.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TrpgPrivateMailboxScreen(
          currentPlayerId: 'human',
          contacts: const [TrpgPrivateContact(id: 'friend', name: '朋友')],
          messages: const [],
          resolveName: (id) => id,
          messageListenable: updates,
          onSend: (_, _) async => null,
        ),
      ),
    );
    await tester.tap(find.text('朋友'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '只留在私聊里的消息');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    updates.value = const [];
    await tester.pump();
    expect(find.text('只留在私聊里的消息'), findsOneWidget);
  });
}
