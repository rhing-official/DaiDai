import 'dart:async';

import 'package:daidai/features/chat/chat_screen.dart';
import 'package:daidai/features/guide/tutorial/practice_home.dart';
import 'package:daidai/features/guide/tutorial/tutorial_controller.dart';
import 'package:daidai/features/guide/tutorial/tutorial_overlay.dart';
import 'package:daidai/features/guide/tutorial/tutorial_stage_screen.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/tutorial_content.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/chat_layout_style.dart';
import 'package:daidai/models/conversation_sort_order.dart';
import 'package:daidai/models/message_time_format.dart';
import 'package:daidai/models/send_key_mode.dart';
import 'package:daidai/models/talks_list_layout_style.dart';
import 'package:daidai/models/calendar_week_start.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/calendar_week_start_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/chat_layout_style_provider.dart';
import 'package:daidai/providers/conversation_sort_order_provider.dart';
import 'package:daidai/providers/draft_sync_enabled_provider.dart';
import 'package:daidai/providers/last_opened_room_provider.dart';
import 'package:daidai/providers/message_time_format_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:daidai/providers/talks_list_layout_style_provider.dart';
import 'package:daidai/repositories/album_repository.dart';
import 'package:daidai/repositories/block_repository.dart';
import 'package:daidai/repositories/calendar_category_repository.dart';
import 'package:daidai/repositories/calendar_event_repository.dart';
import 'package:daidai/repositories/call_repository.dart';
import 'package:daidai/repositories/conversation_prefs_repository.dart';
import 'package:daidai/repositories/direct_message_repository.dart';
import 'package:daidai/repositories/friend_repository.dart';
import 'package:daidai/repositories/group_call_repository.dart';
import 'package:daidai/repositories/group_repository.dart';
import 'package:daidai/repositories/note_repository.dart';
import 'package:daidai/repositories/poll_repository.dart';
import 'package:daidai/repositories/schedule_coordination_repository.dart';
import 'package:daidai/repositories/sticker_repository.dart';
import 'package:daidai/repositories/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

// 使い方ガイドの練習用の画面が、本物（アプリ全体）のリポジトリへ一切触れないこと
// （2026-10-17）。設定から開く場合、練習用の画面の下には本物のホームがあり、アプリ
// 全体のリポジトリは本物のFirestoreを指す。ここでは本物側を「呼ばれたら記録する
// だけ」の偽にして、練習中に呼ばれていないことを確かめる。

final _calls = <String>[];

mixin _Recording {
  String get label;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    _calls.add('$label.${invocation.memberName}');
    final name = invocation.memberName.toString();
    if (name.contains('"watch')) return const Stream<Never>.empty();
    return Completer<Never>().future;
  }
}

class _User with _Recording implements UserRepository {
  @override
  String get label => 'user';
}

class _Dm with _Recording implements DirectMessageRepository {
  @override
  String get label => 'dm';
}

class _Group with _Recording implements GroupRepository {
  @override
  String get label => 'group';
}

class _Friend with _Recording implements FriendRepository {
  @override
  String get label => 'friend';
}

class _Block with _Recording implements BlockRepository {
  @override
  String get label => 'block';
}

class _Prefs with _Recording implements ConversationPrefsRepository {
  @override
  String get label => 'prefs';
}

class _Sticker with _Recording implements StickerRepository {
  @override
  String get label => 'sticker';
}

class _Album with _Recording implements AlbumRepository {
  @override
  String get label => 'album';
}

class _CalEvent with _Recording implements CalendarEventRepository {
  @override
  String get label => 'calEvent';
}

class _CalCat with _Recording implements CalendarCategoryRepository {
  @override
  String get label => 'calCat';
}

class _Schedule with _Recording implements ScheduleCoordinationRepository {
  @override
  String get label => 'schedule';
}

class _Poll with _Recording implements PollRepository {
  @override
  String get label => 'poll';
}

class _Note with _Recording implements NoteRepository {
  @override
  String get label => 'note';
}

class _Call with _Recording implements CallRepository {
  @override
  String get label => 'call';
}

class _GroupCall with _Recording implements GroupCallRepository {
  @override
  String get label => 'groupCall';
}

/// 練習用の画面を、アプリ全体のリポジトリが「呼ばれたら記録する偽」の状態で開き、
/// [script]を始める。
Future<void> _pumpPractice(
  WidgetTester tester,
  Size size,
  TutorialScript script,
) async {
  _calls.clear();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
        initialDraftSyncEnabledProvider.overrideWithValue(true),
        initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
        initialCalendarWeekStartProvider.overrideWithValue(
          CalendarWeekStart.sunday,
        ),
        userRepositoryProvider.overrideWithValue(_User()),
        directMessageRepositoryProvider.overrideWithValue(_Dm()),
        groupRepositoryProvider.overrideWithValue(_Group()),
        friendRepositoryProvider.overrideWithValue(_Friend()),
        blockRepositoryProvider.overrideWithValue(_Block()),
        conversationPrefsRepositoryProvider.overrideWithValue(_Prefs()),
        stickerRepositoryProvider.overrideWithValue(_Sticker()),
        albumRepositoryProvider.overrideWithValue(_Album()),
        calendarEventRepositoryProvider.overrideWithValue(_CalEvent()),
        calendarCategoryRepositoryProvider.overrideWithValue(_CalCat()),
        scheduleCoordinationRepositoryProvider.overrideWithValue(_Schedule()),
        pollRepositoryProvider.overrideWithValue(_Poll()),
        noteRepositoryProvider.overrideWithValue(_Note()),
        callRepositoryProvider.overrideWithValue(_Call()),
        groupCallRepositoryProvider.overrideWithValue(_GroupCall()),
      ],
      child: MaterialApp(
        home: TutorialStageScreen(
          startScript: script,
          onClosed: () {},
          child: const PracticeHome(),
        ),
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
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openChat(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.forum_outlined));
  await _settle(tester);
  await tester.tap(find.textContaining('@daidai').first);
  await _settle(tester);
}

TutorialState? _state(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(TutorialStageScreen)),
).read(tutorialControllerProvider);

void main() {
  setUpAll(() => initializeDateFormatting('ja'));
  for (final size in [const Size(800, 1400), const Size(1400, 900)]) {
    testWidgets('練習中（メッセージの送信まで）に本物のリポジトリは呼ばれない（$size）', (tester) async {
      await _pumpPractice(tester, size, messagesTutorial);
      await _openChat(tester);
      final composer = find.descendant(
        of: find.byType(ChatScreen),
        matching: find.byType(TextField),
      );
      await tester.enterText(composer, 'こんにちは');
      await _settle(tester);
      await tester.tap(find.byIcon(Icons.send));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 2));
      // 下書きの同期が有効な設定でも、送ったメッセージが会話に出る（入力欄は空）。
      expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
      expect(find.text('こんにちは'), findsWidgets);
      expect(_calls, isEmpty, reason: _calls.toSet().join('\n'));
    });

    testWidgets('一対と広場のガイドを通して進められ、本物のリポジトリは呼ばれない（$size）', (tester) async {
      await _pumpPractice(tester, size, directPlazaTutorial);
      await tester.tap(find.byIcon(Icons.forum_outlined));
      await _settle(tester);
      expect(_state(tester)?.index, 1);
      await tester.tap(find.byKey(const ValueKey('tutorial-next')));
      await _settle(tester);
      expect(_state(tester)?.index, 2);
      await tester.tap(find.textContaining('広場').first);
      await _settle(tester);
      expect(_state(tester)?.index, 3);
      await tester.tap(find.byKey(const ValueKey('tutorial-next')));
      await _settle(tester);
      expect(_state(tester)?.done, isTrue);
      expect(_calls, isEmpty, reason: _calls.toSet().join('\n'));
    });

    testWidgets('通話のガイドは、電話ボタンを説明して完了する（$size）', (tester) async {
      await _pumpPractice(tester, size, callsTutorial);
      await _openChat(tester);
      expect(_state(tester)?.index, 2);
      await tester.tap(find.byKey(const ValueKey('tutorial-next')));
      await _settle(tester);
      expect(_state(tester)?.done, isTrue);
      expect(_calls, isEmpty, reason: _calls.toSet().join('\n'));
    });

    testWidgets('notesのガイドは、見本のノートを開いて書き方を説明し、閉じると元に戻れる（$size）', (
      tester,
    ) async {
      await _pumpPractice(tester, size, notesTutorial);
      await _openChat(tester);
      expect(_state(tester)?.index, 2);
      await tester.tap(find.byIcon(Icons.note_alt_outlined).first);
      await _settle(tester);
      expect(_state(tester)?.index, 3);
      // 一覧に、見本のノートだけが出る。
      expect(find.textContaining('旅行の持ち物'), findsWidgets);
      await tester.tap(find.textContaining('旅行の持ち物').first);
      await _settle(tester);
      await _settle(tester);
      expect(_state(tester)?.index, 4);
      // 書き方の説明（情報の手順）を「次へ」で最後まで進める。
      while (_state(tester)?.done != true) {
        final before = (_state(tester)?.index, _state(tester)?.done);
        await tester.tap(find.byKey(const ValueKey('tutorial-next')));
        await _settle(tester);
        expect(
          (_state(tester)?.index, _state(tester)?.done) == before,
          isFalse,
        );
      }
      expect(_calls, isEmpty, reason: _calls.toSet().join('\n'));
      await tester.tap(find.widgetWithText(ElevatedButton, '閉じる'));
      await _settle(tester);
      expect(find.byWidgetPredicate((w) => w is PopupMenuItem), findsNothing);
    });

    for (final (script, IconData icon) in [
      (albumTutorial, Icons.photo_library_outlined),
      (calendarTutorial, Icons.event_outlined),
    ]) {
      testWidgets('${script.id}のガイドは、ボタンを押して開いて完了する（$size）', (tester) async {
        await _pumpPractice(tester, size, script);
        await _openChat(tester);
        expect(_state(tester)?.index, 2);
        final targetId = script.steps.last.targetId;
        // 目印のボタンを押す（アイコンでなく、案内の層が指している場所を押す）。
        final button = find.byIcon(icon).first;
        expect(targetId, isNotEmpty);
        await tester.tap(button);
        await _settle(tester);
        await _settle(tester);
        expect(_state(tester)?.done, isTrue);
        expect(_calls, isEmpty, reason: _calls.toSet().join('\n'));
        // 完了を押してガイドを終えたら、開いていたメニュー（ノート・アルバムの一覧）も
        // 閉じる（残ると、練習用の画面に取り残されて戻れなくなる）。
        await tester.tap(find.widgetWithText(ElevatedButton, '閉じる'));
        await _settle(tester);
        expect(find.byWidgetPredicate((w) => w is PopupMenuItem), findsNothing);
      });
    }
  }
}
