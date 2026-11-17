import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/models/direct_message.dart';
import 'package:daidai/models/friend_request.dart';
import 'package:daidai/widgets/unread_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FriendRequest _request() => FriendRequest(
  requestId: 'a_b',
  fromUserId: 'a',
  fromRhingSeed: 'alice',
  toUserId: 'b',
  toRhingSeed: 'bob',
  status: FriendRequestStatus.pending,
  createdAt: Timestamp.fromDate(DateTime(2026, 11, 17, 12)),
);

void main() {
  group('DirectMessage.pendingFrom', () {
    test('申請から、表示用の一対を作る（idは決定的、両者のSeedを持つ）', () {
      final dm = DirectMessage.pendingFrom(_request());
      expect(dm.dmId, 'a_b');
      expect(dm.dmId, DirectMessage.idFor('b', 'a'));
      expect(dm.participants, ['a', 'b']);
      expect(dm.participantRhingSeeds, {'a': 'alice', 'b': 'bob'});
      expect(dm.otherUserId('a'), 'b');
      expect(dm.lastMessageAt, _request().createdAt);
    });

    test('メッセージの印は持たない（プレビュー・種類なし）', () {
      final dm = DirectMessage.pendingFrom(_request());
      expect(dm.lastMessagePreview, isNull);
      expect(dm.lastMessageContentType, isNull);
    });
  });

  group('UnreadBadge', () {
    testWidgets('通常は件数、attentionは「!」を出す', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [UnreadBadge(count: 3), UnreadBadge.attention()],
          ),
        ),
      );
      expect(find.text('3'), findsOneWidget);
      expect(find.text('!'), findsOneWidget);
    });

    testWidgets('件数は99を超えると99+', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: UnreadBadge(count: 120)));
      expect(find.text('99+'), findsOneWidget);
    });
  });
}
