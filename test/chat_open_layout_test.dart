import 'dart:async';

import 'package:daidai/features/chat/chat_screen.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Enterキーの送信/改行/通知なし送信の振り分けが実際に効くかどうかを検証する回帰テスト。
// Focus.onKeyEventでEnterを消費する実装がFlutterの本物のキーイベント経路
// （EditableTextの改行挿入と競合しないか）は理屈だけでは確信が持てない為、
// 実際にキーイベントを流して確認する。

// 回帰テスト（2026-11-08）: メッセージの最初のデータが届く前（読み込み表示だけの
// 最初の数フレーム）に、入力欄が幅0で配置されて文字が1文字ずつ折り返し、背の高い
// 入力欄（実測192〜254px）として計測されると、一覧の下余白に誤って使われ、
// 直後に縮んで内容全体が動いて見えた。
void main() {
  testWidgets('メッセージが届く前でも、入力欄は画面幅いっぱいで1行の高さになる', (tester) async {
    tester.view.physicalSize = const Size(412, 868);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = StreamController<List<Message>>();
    addTearDown(controller.close);
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
            isDm: true,
            messagesStream: controller.stream,
            onSend:
                (
                  content, {
                  silent = false,
                  replyTo,
                  mentions = MessageMentions.none,
                  sendAt,
                }) async {},
          ),
        ),
      ),
    );
    final field = tester.getSize(find.byType(TextField));
    expect(field.width, greaterThan(200));
    expect(field.height, lessThan(100));
  });
}
