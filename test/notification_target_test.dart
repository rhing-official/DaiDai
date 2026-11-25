import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daidai/utils/notification_target.dart';

void main() {
  group('needsAccountSwitch', () {
    test('宛先が無い通知は切り替えない（古い通知・古いサーバー）', () {
      expect(needsAccountSwitch(null, 'a'), isFalse);
      expect(needsAccountSwitch('', 'a'), isFalse);
    });

    test('宛先が今のアカウントと同じなら切り替えない', () {
      expect(needsAccountSwitch('a', 'a'), isFalse);
    });

    test('宛先が今のアカウントと違えば切り替える', () {
      expect(needsAccountSwitch('b', 'a'), isTrue);
    });

    test('今のアカウントがまだ分からない間は、判断を後に回す', () {
      expect(needsAccountSwitch('b', null), isTrue);
    });
  });

  group('NotificationTarget', () {
    const target = NotificationTarget(
      kind: NotificationTargetKind.callAnswer,
      recipientId: 'b',
      data: {'kind': 'dm', 'callId': 'c1', 'groupId': null},
      createdAtMs: 1000,
    );

    test('JSONへ往復できる', () {
      final back = NotificationTarget.tryFromJson(target.toJson());
      expect(back, isNotNull);
      expect(back!.kind, NotificationTargetKind.callAnswer);
      expect(back.recipientId, 'b');
      expect(back.data['callId'], 'c1');
      expect(back.createdAtMs, 1000);
    });

    test('壊れた入力はnullになる', () {
      expect(NotificationTarget.tryFromJson(null), isNull);
      expect(NotificationTarget.tryFromJson({'kind': 'chat'}), isNull);
      expect(
        NotificationTarget.tryFromJson({
          'kind': 'unknown',
          'recipientId': 'b',
          'data': <String, dynamic>{},
          'createdAtMs': 1,
        }),
        isNull,
      );
      expect(
        NotificationTarget.tryFromJson({
          'kind': 'chat',
          'recipientId': '',
          'data': <String, dynamic>{},
          'createdAtMs': 1,
        }),
        isNull,
      );
    });

    test('期限は3分', () {
      final limit = kNotificationTargetTtl.inMilliseconds;
      expect(target.isExpired(1000 + limit), isFalse);
      expect(target.isExpired(1000 + limit + 1), isTrue);
    });
  });

  group('保存', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('保存した行き先を、1度だけ取り出せる', () async {
      const target = NotificationTarget(
        kind: NotificationTargetKind.chat,
        recipientId: 'b',
        data: {'payload': '{"conversationId":"x"}'},
        createdAtMs: 5000,
      );
      await savePendingNotificationTarget(target);
      final first = await takeSavedNotificationTarget(5000);
      expect(first?.recipientId, 'b');
      expect(first?.data['payload'], '{"conversationId":"x"}');
      expect(await takeSavedNotificationTarget(5000), isNull);
    });

    test('期限切れの行き先は取り出せず、消える', () async {
      const target = NotificationTarget(
        kind: NotificationTargetKind.chat,
        recipientId: 'b',
        data: {'payload': 'p'},
        createdAtMs: 0,
      );
      await savePendingNotificationTarget(target);
      final late = kNotificationTargetTtl.inMilliseconds + 1;
      expect(await takeSavedNotificationTarget(late), isNull);
      expect(await takeSavedNotificationTarget(0), isNull);
    });

    test('今のアカウントのidを書ける', () async {
      await publishCurrentAccountId('a');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kCurrentAccountIdKey), 'a');
    });

    test('保存した行き先の有無を、取り出さずに調べられる', () async {
      expect(await hasSavedNotificationTarget(), isFalse);
      await savePendingNotificationTarget(
        const NotificationTarget(
          kind: NotificationTargetKind.callAnswer,
          recipientId: 'b',
          data: {'callId': 'c'},
          createdAtMs: 0,
        ),
      );
      expect(await hasSavedNotificationTarget(), isTrue);
      expect(await hasSavedNotificationTarget(), isTrue);
      expect(await takeSavedNotificationTarget(0), isNotNull);
      expect(await hasSavedNotificationTarget(), isFalse);
    });
  });
}
