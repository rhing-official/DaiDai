import 'package:daidai/features/chat/chat_screen.dart';
import 'package:daidai/features/chat/mention_suggestion_list.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/chat_layout_style.dart';
import 'package:daidai/models/message.dart';
import 'package:daidai/models/message_time_format.dart';
import 'package:daidai/models/send_key_mode.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/chat_layout_style_provider.dart';
import 'package:daidai/providers/message_time_format_provider.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:daidai/utils/mention_suggestion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 入力欄の`@`メンション（サジェスト表示・キー操作・送信時の宛先）の回帰テスト。
const _candidates = [
  MentionCandidate(
    kind: MentionKind.user,
    id: 'u2',
    label: '新',
    subtitle: 'arata',
  ),
  MentionCandidate(
    kind: MentionKind.user,
    id: 'u3',
    label: '社長',
    subtitle: 'kaina',
  ),
  MentionCandidate(kind: MentionKind.everyone, id: '', label: 'everyone'),
];

class _Sent {
  const _Sent(this.content, this.mentions);
  final String content;
  final MessageMentions mentions;
}

Future<void> _pump(WidgetTester tester, List<_Sent> sent) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialSendKeyModeProvider.overrideWithValue(SendKeyMode.enterToSend),
        initialMessageTimeFormatProvider.overrideWithValue(
          MessageTimeFormat.h24,
        ),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialChatLayoutStyleProvider.overrideWithValue(
          ChatLayoutStyle.sideBySide,
        ),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
      ],
      child: MaterialApp(
        home: ChatScreen(
          title: 'test',
          currentUserId: 'u1',
          isDm: false,
          messagesStream: Stream.value(<Message>[]),
          mentionCandidates: _candidates,
          onSend:
              (
                content, {
                silent = false,
                replyTo,
                mentions = MessageMentions.none,
              }) async => sent.add(_Sent(content, mentions)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _desktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('@を打つと「メンバー」区分に@everyoneも含めて候補が出て、全角＠では出ない', (tester) async {
    final sent = <_Sent>[];
    await _pump(tester, sent);

    await tester.enterText(find.byType(TextField), '＠');
    await tester.pump();
    expect(find.byType(MentionSuggestionList), findsNothing);

    await tester.enterText(find.byType(TextField), '@');
    await tester.pump();
    expect(find.byType(MentionSuggestionList), findsOneWidget);
    expect(find.text('メンバー'), findsOneWidget);
    expect(find.text('その他'), findsNothing);
    expect(find.text('@everyone'), findsOneWidget);
  });

  testWidgets('入力で絞り込み、Enterは送信せず候補を確定する→次のEnterで宛先付きで送信', (tester) async {
    await _desktop(() async {
      final sent = <_Sent>[];
      await _pump(tester, sent);

      await tester.enterText(find.byType(TextField), 'こんにちは @社');
      await tester.pump();
      expect(find.text('社長'), findsOneWidget);
      expect(find.text('新'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(find.byType(MentionSuggestionList), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'こんにちは @社長 ',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(sent.single.mentions.userIds, ['u3']);
      expect(sent.single.mentions.labels, ['@社長']);
    });
  });

  testWidgets('↓で選択を移し、Escで閉じる。挿入後に@名前を消すと宛先から外れる', (tester) async {
    await _desktop(() async {
      final sent = <_Sent>[];
      await _pump(tester, sent);

      await tester.enterText(find.byType(TextField), '@');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '@社長 ',
      );

      // 宛先を消してから送信すると、メンション情報は付かない。
      await tester.enterText(find.byType(TextField), 'やっぱり');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(sent.single.mentions.isEmpty, isTrue);

      await tester.enterText(find.byType(TextField), '@');
      await tester.pump();
      expect(find.byType(MentionSuggestionList), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(MentionSuggestionList), findsNothing);
    });
  });
}
