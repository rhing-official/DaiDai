import 'package:daidai/features/chat/chat_screen.dart';
import 'package:daidai/features/guide/first_run_tutorial_screen.dart';
import 'package:daidai/features/guide/tutorial/tutorial_controller.dart';
import 'package:daidai/features/guide/tutorial/tutorial_overlay.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/chat_layout_style.dart';
import 'package:daidai/models/message_time_format.dart';
import 'package:daidai/models/send_key_mode.dart';
import 'package:daidai/models/conversation_sort_order.dart';
import 'package:daidai/models/talks_list_layout_style.dart';
import 'package:daidai/providers/conversation_sort_order_provider.dart';
import 'package:daidai/providers/draft_sync_enabled_provider.dart';
import 'package:daidai/providers/last_opened_room_provider.dart';
import 'package:daidai/providers/talks_list_layout_style_provider.dart';
import 'package:daidai/providers/chat_layout_style_provider.dart';
import 'package:daidai/providers/message_time_format_provider.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/guide_content.dart';
import 'package:daidai/models/app_user_preferences.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUserRepository implements UserRepository {
  final writes = <(String, String, Object?)>[];
  bool failWrite = false;

  @override
  Future<void> updateUserPreference(
    String userId,
    String field,
    Object? value,
  ) async {
    if (failWrite) throw StateError('offline');
    writes.add((userId, field, value));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 案内の層は毎フレーム更新されるためpumpAndSettleは終わらない。時間だけ進める。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_FakeUserRepository> _pump(
  WidgetTester tester, {
  required VoidCallback onCompleted,
  String userId = 'u1',
  Size size = const Size(800, 1400),
  bool failWrite = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = _FakeUserRepository()..failWrite = failWrite;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        initialSendKeyModeProvider.overrideWithValue(SendKeyMode.enterToSend),
        initialMessageTimeFormatProvider.overrideWithValue(
          MessageTimeFormat.h24,
        ),
        initialChatLayoutStyleProvider.overrideWithValue(
          ChatLayoutStyle.sideBySide,
        ),
        initialTalksListLayoutStyleProvider.overrideWithValue(
          TalksListLayoutStyle.standard,
        ),
        initialConversationSortOrderProvider.overrideWithValue(
          ConversationSortOrder.recent,
        ),
        initialLastOpenedRoomsProvider.overrideWithValue(const {}),
        initialDraftSyncEnabledProvider.overrideWithValue(false),
        userRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: FirstRunTutorialScreen(userId: userId, onCompleted: onCompleted),
        builder: (context, child) => Stack(
          children: [
            Positioned.fill(child: child ?? const SizedBox.shrink()),
            const TutorialOverlay(),
          ],
        ),
      ),
    ),
  );
  await _settle(tester);
  return repo;
}

void main() {
  group('ガイドの内容', () {
    test('機能別ガイドのidに重複が無く、日英とも本文が空でない', () {
      final ids = guideTopics.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final topic in guideTopics) {
        expect(topic.steps, isNotEmpty, reason: topic.id);
        for (final text in [topic.title, topic.summary, ...topic.steps]) {
          expect(text.ja.trim(), isNotEmpty, reason: topic.id);
          expect(text.en.trim(), isNotEmpty, reason: topic.id);
        }
      }
    });
  });

  group('guideSeen', () {
    test('未設定（既存住人）はnullで、JSONにも出ない', () {
      final prefs = AppUserPreferences.fromJson(const {});
      expect(prefs.guideSeen, isNull);
      expect(prefs.toJson().containsKey('guideSeen'), isFalse);
    });

    test('false（新規で未視聴）とtrue（視聴済み）がJSONで往復する', () {
      for (final value in [false, true]) {
        final prefs = AppUserPreferences(guideSeen: value);
        expect(prefs.toJson()['guideSeen'], value);
        expect(AppUserPreferences.fromJson(prefs.toJson()).guideSeen, value);
      }
    });
  });

  group('FirstRunTutorialScreen', () {
    testWidgets('開くと初回のガイドが始まり、最初に「身だしなみ」を案内する', (tester) async {
      await _pump(tester, onCompleted: () {});
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FirstRunTutorialScreen)),
      );
      expect(
        container.read(tutorialControllerProvider)?.script.id,
        'first-run',
      );
      expect(find.text('まず「身だしなみ」を押します'), findsOneWidget);
    });

    testWidgets('「やめる」でも視聴済みを記録して完了を1回だけ通知する', (tester) async {
      var completed = 0;
      final repo = await _pump(tester, onCompleted: () => completed++);
      await tester.tap(find.text('やめる'));
      await _settle(tester);
      expect(completed, 1);
      expect(repo.writes, [('u1', 'guideSeen', true)]);
    });

    testWidgets('記録の書き込みに失敗しても先へ進める', (tester) async {
      var completed = 0;
      await _pump(tester, failWrite: true, onCompleted: () => completed++);
      await tester.tap(find.text('やめる'));
      await _settle(tester);
      expect(completed, 1);
    });

    for (final (label, size) in [
      ('縦長（モバイル）', const Size(800, 1400)),
      ('横長（コンピューター）', const Size(1400, 900)),
    ])
      testWidgets('身だしなみ→縁結び→メッセージの送信まで押して進み、完了カードで終えられる（$label）', (
        tester,
      ) async {
        var completed = 0;
        final repo = await _pump(
          tester,
          size: size,
          onCompleted: () => completed++,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(FirstRunTutorialScreen)),
        );
        int index() => container.read(tutorialControllerProvider)!.index;

        Future<void> next() async {
          await tester.tap(find.byKey(const ValueKey('tutorial-next')));
          await _settle(tester);
        }

        // 身だしなみ（チップ→蔵・仕立ての説明）。
        await tester.tap(find.byIcon(Icons.face_outlined));
        await _settle(tester);
        expect(index(), 1);
        // 蔵の説明中は蔵の中身が、仕立ての説明中は仕立ての中身が右側に出る（広い画面）。
        expect(find.textContaining('アイコン'), findsWidgets);
        await next();
        expect(index(), 2);
        expect(find.textContaining('アイコン'), findsNothing);
        await next();
        // 縁結び（行→コピー→QR→読み取り）。
        expect(index(), 3);
        await tester.tap(find.text('縁結び').last);
        await _settle(tester);
        await _settle(tester);
        await tester.tap(find.byIcon(Icons.copy_outlined));
        await _settle(tester);
        await next();
        await next();
        // メッセージ（語らい→相手→入力→送信）。
        expect(index(), 7);
        await tester.tap(find.byIcon(Icons.forum_outlined));
        await _settle(tester);
        await tester.tap(find.textContaining('@daidai').first);
        await _settle(tester);
        expect(index(), 9);
        // 入力欄に文字を入れると送信ボタンが現れて、次の手順へ進む（会話の入力欄を指す）。
        final composer = find.descendant(
          of: find.byType(ChatScreen),
          matching: find.byType(TextField),
        );
        await tester.enterText(composer, 'こんにちは');
        await _settle(tester);
        expect(index(), 10);
        // 文字を消して送信ボタンが消えても、入力欄は明るく抜かれたままで入力し直せる。
        await tester.enterText(composer, '');
        await _settle(tester);
        expect(index(), 10);
        await tester.enterText(composer, 'こんにちは');
        await _settle(tester);
        await tester.tap(find.byIcon(Icons.send));
        await _settle(tester);
        // 送ったメッセージが練習用の会話に出る。
        // 入力欄は空になり、メッセージ（広い画面は一覧のプレビューにも）が出る。
        expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
        expect(find.text('こんにちは'), findsWidgets);

        expect(container.read(tutorialControllerProvider)?.done, isTrue);
        expect(find.textContaining('「使い方ガイド」'), findsOneWidget);
        await tester.tap(find.text('閉じる'));
        await _settle(tester);
        expect(completed, 1);
        expect(repo.writes, [('u1', 'guideSeen', true)]);
        // 残ったタイマーを進めて片付ける。
        await tester.pump(const Duration(seconds: 2));
      });
  });
}
