import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/features/chat/scheduled_send_ui.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/message.dart';
import 'package:daidai/models/scheduled_message.dart';
import 'package:daidai/utils/attachment_upload.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/scheduled_message_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeScheduledRepo implements ScheduledMessageRepository {
  _FakeScheduledRepo(this.items);
  final List<ScheduledMessage> items;
  final List<String> cancelled = [];

  @override
  Stream<List<ScheduledMessage>> watch({
    required String userId,
    required String conversationId,
    required String roomId,
  }) => Stream.value(items);

  @override
  Future<void> cancel(ScheduledMessage scheduled) async =>
      cancelled.add(scheduled.id);

  @override
  Future<void> reschedule(String id, DateTime sendAt) async {}

  @override
  Future<void> updateContent(
    ScheduledMessage scheduled, {
    required String text,
    required List<MessageFileMetadata> kept,
    required List<AttachmentUploadInput> added,
    ValueChanged<double>? onProgress,
  }) async {}
}

ScheduledMessage _item(
  String id, {
  String content = 'こんにちは',
  String status = 'pending',
  String? failReason,
}) => ScheduledMessage(
  id: id,
  scope: 'dm',
  conversationId: 'c',
  roomId: 'r',
  messageId: 'm$id',
  message: {'content': content, 'contentType': 'text'},
  createdBy: 'u',
  sendAt: DateTime.now().add(const Duration(days: 1)),
  status: status,
  failReason: failReason,
);

void main() {
  test('予定の日時は未来から31日後まで', () {
    final now = DateTime(2026, 11, 10, 12);
    expect(isScheduledTimeAllowed(now, now), isFalse);
    expect(
      isScheduledTimeAllowed(now.add(const Duration(minutes: 1)), now),
      isTrue,
    );
    expect(
      isScheduledTimeAllowed(now.add(const Duration(days: 31)), now),
      isTrue,
    );
    expect(
      isScheduledTimeAllowed(
        now.add(const Duration(days: 31, seconds: 1)),
        now,
      ),
      isFalse,
    );
  });

  test('予定の保存内容には送信時刻（sentAt）を含めない', () {
    final json = ScheduledMessage.toCreateJson(
      scope: 'group',
      conversationId: 'g',
      roomId: 'r',
      messageId: 'm',
      message: {'content': 'x', 'sentAt': 'sentinel'},
      createdBy: 'u',
      sendAt: DateTime(2026, 12, 1),
      lastMessageContentType: 'text',
      lastMessagePreview: 'x',
    );
    expect((json['message'] as Map).containsKey('sentAt'), isFalse);
    expect(json['status'], 'pending');
    expect(json['sendAt'], isA<Timestamp>());
  });

  test('日時の表示: 今年は月/日、他の年は年も付ける', () {
    final now = DateTime(2026, 11, 10);
    expect(
      formatScheduledTime(DateTime(2026, 12, 1, 9, 5), now: now),
      '12/1 09:05',
    );
    expect(
      formatScheduledTime(DateTime(2027, 1, 2, 23, 0), now: now),
      '2027/1/2 23:00',
    );
  });

  testWidgets('一覧: 予定が並び、失敗は理由つき、取り消しで確認後に消える', (tester) async {
    final repo = _FakeScheduledRepo([
      _item('1'),
      _item('2', content: '失敗した', status: 'failed', failReason: 'notMember'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
          scheduledMessageRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showScheduledMessagesDialog(
                context: context,
                userId: 'u',
                conversationId: 'c',
                roomId: 'r',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('こんにちは'), findsOneWidget);
    expect(find.textContaining('この会話に参加していません'), findsOneWidget);
    // 送信待ちだけ日時の変更ボタンがある。
    expect(find.byIcon(Icons.edit_calendar_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取り消す').last);
    await tester.pumpAndSettle();
    expect(repo.cancelled, ['1']);
  });
}
