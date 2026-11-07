import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/features/poll/poll_message_card.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/poll.dart';
import 'package:daidai/models/poll_response.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/poll_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePollRepository implements PollRepository {
  _FakePollRepository(this.poll);

  final Poll? poll;
  final List<List<String>> votes = [];

  @override
  Stream<Poll?> watchPoll({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
  }) => Stream.value(poll);

  @override
  Stream<PollResponse?> watchMyResponse({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
    required String userId,
  }) => Stream.value(null);

  @override
  Future<void> castVote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String pollId,
    required String userId,
    required List<String> selectedOptionKeys,
  }) async {
    votes.add(selectedOptionKeys);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Poll _poll({int options = 2, DateTime? deadline, bool withImage = false}) {
  return Poll(
    pollId: 'p',
    roomId: 'r',
    question: '昼ご飯は？',
    options: {
      for (var i = 0; i < options; i++)
        '$i': PollOption(
          text: '選択肢$i',
          mediaUrl: withImage && i == 0 ? 'https://example.com/a.png' : null,
          mediaType: withImage && i == 0 ? 'image' : null,
        ),
    },
    createdBy: 'u',
    deadline: deadline == null ? null : Timestamp.fromDate(deadline),
  );
}

Future<_FakePollRepository> _pump(WidgetTester tester, Poll? poll) async {
  final repo = _FakePollRepository(poll);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        pollRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PollMessageCard(
            isDm: true,
            conversationId: 'c',
            roomId: 'r',
            pollId: 'p',
            currentUserId: 'me',
            foreground: Colors.black,
            fallback: const Text('FALLBACK'),
            frame: (inner) => Material(child: inner),
            onOpen: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return repo;
}

void main() {
  testWidgets('少ない選択肢の投票は、メッセージ内で選んで投票できる', (tester) async {
    final repo = await _pump(tester, _poll());
    expect(find.text('昼ご飯は？'), findsOneWidget);
    expect(find.text('FALLBACK'), findsNothing);
    // 選ぶまでは投票できない。
    final voteButton = find.widgetWithText(FilledButton, '投票する');
    expect(tester.widget<FilledButton>(voteButton).onPressed, isNull);

    await tester.tap(find.textContaining('選択肢1'));
    await tester.pump();
    await tester.tap(voteButton);
    await tester.pump();
    expect(repo.votes, [
      ['1'],
    ]);
  });

  testWidgets('選択肢が5件以上・画像付きは従来の小さいカードに折りたたむ', (tester) async {
    await _pump(tester, _poll(options: 5));
    expect(find.text('FALLBACK'), findsOneWidget);
    await _pump(tester, _poll(withImage: true));
    expect(find.text('FALLBACK'), findsOneWidget);
  });

  testWidgets('投票が取得できない（削除済み）ときも従来のカード', (tester) async {
    await _pump(tester, null);
    expect(find.text('FALLBACK'), findsOneWidget);
  });

  testWidgets('期限切れの投票は投票できない', (tester) async {
    await _pump(
      tester,
      _poll(deadline: DateTime.now().subtract(const Duration(days: 1))),
    );
    await tester.tap(find.textContaining('選択肢0'));
    await tester.pump();
    final voteButton = find.widgetWithText(FilledButton, '投票する');
    expect(tester.widget<FilledButton>(voteButton).onPressed, isNull);
    expect(find.textContaining('終了'), findsOneWidget);
  });
}
