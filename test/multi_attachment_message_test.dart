import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/features/chat/chat_screen.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/chat_layout_style.dart';
import 'package:daidai/models/message.dart';
import 'package:daidai/models/message_time_format.dart';
import 'package:daidai/models/send_key_mode.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/chat_layout_style_provider.dart';
import 'package:daidai/providers/message_time_format_provider.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 複数添付メッセージ（contentType=multi）のビューア展開と、バブルの描画の回帰テスト。
MessageFileMetadata _meta(String name, String mime) => MessageFileMetadata(
  url: 'https://example.invalid/$name',
  fileName: name,
  extension: name.split('.').last,
  sizeBytes: 100,
  mimeType: mime,
);

Message _multi(String id, List<MessageFileMetadata> attachments) => Message(
  messageId: id,
  conversationId: 'c',
  conversationType: 'room',
  senderId: 'u2',
  content: attachments.map((a) => a.fileName).join(' / '),
  contentType: 'multi',
  sentAt: Timestamp.fromMillisecondsSinceEpoch(1000),
  fileMetadata: attachments.first,
  attachments: attachments,
);

void main() {
  test('mediaViewerItemsOfは複数添付の画像・動画だけを1枚ずつ展開する', () {
    final single = Message(
      messageId: 's1',
      conversationId: 'c',
      conversationType: 'room',
      senderId: 'u2',
      content: 'x.webp',
      contentType: 'image',
      fileMetadata: _meta('x.webp', 'image/webp'),
    );
    final multi = _multi('m1', [
      _meta('a.webp', 'image/webp'),
      _meta('doc.pdf', 'application/pdf'),
      _meta('b.mp4', 'video/mp4'),
    ]);
    final items = mediaViewerItemsOf([single, multi]);
    expect(items.map((i) => i.id), ['s1', 'm1#0', 'm1#2']);
    expect(items.map((i) => i.contentType), ['image', 'image', 'video']);
  });

  for (final count in [2, 3, 4, 5, 6, 7, 8, 9, 10]) {
    testWidgets('画像$count枚のグリッドを描画できる', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final message = _multi('m1', [
        for (var i = 0; i < count; i++) _meta('p$i.webp', 'image/webp'),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAccentColorProvider.overrideWithValue(Colors.orange),
            initialSendKeyModeProvider.overrideWithValue(
              SendKeyMode.enterToSend,
            ),
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
              title: 't',
              currentUserId: 'u1',
              isDm: false,
              messagesStream: Stream.value([message]),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNWidgets(count));
    });
  }

  testWidgets('動画を含む複数添付（サムネイルなし）も例外なく描画できる', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final message = _multi('m1', [
      _meta('a.mp4', 'video/mp4'),
      _meta('b.mp4', 'video/mp4'),
      _meta('c.webp', 'image/webp'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAccentColorProvider.overrideWithValue(Colors.orange),
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
            title: 't',
            currentUserId: 'u1',
            isDm: false,
            messagesStream: Stream.value([message]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsOneWidget);
  });
}
