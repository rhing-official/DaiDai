import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/chat/attachment_popup_button.dart';
import 'package:daidai/features/chat/pending_attachment_tray.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/widgets/media_viewer_screen.dart';
import 'package:daidai/l10n/strings.dart';

// 1x1の透明PNG。
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  final attachments = [
    PickedAttachment(bytes: _png, fileName: 'a.png', contentType: 'image'),
    PickedAttachment(
      bytes: Uint8List(4),
      fileName: 'b.mp4',
      contentType: 'video',
    ),
  ];

  Widget host({
    required List<PickedAttachment> list,
    ValueChanged<int>? onRemove,
    bool enabled = true,
  }) => ProviderScope(
    overrides: [initialAppLocaleProvider.overrideWithValue(AppLocale.japanese)],
    child: MaterialApp(
      home: Scaffold(
        body: PendingAttachmentTray(
          attachments: list,
          strings: Strings.ja,
          onRemove: onRemove ?? (_) {},
          enabled: enabled,
        ),
      ),
    ),
  );

  testWidgets('サムネイルとファイル名を並べ、×で外せる', (tester) async {
    int? removed;
    await tester.pumpWidget(
      host(list: attachments, onRemove: (i) => removed = i),
    );
    expect(find.text('a.png'), findsOneWidget);
    expect(find.text('b.mp4'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNWidgets(2));
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).last);
    expect(removed, 1);
  });

  testWidgets('送信中などで無効な間は、外せない', (tester) async {
    int? removed;
    await tester.pumpWidget(
      host(list: attachments, enabled: false, onRemove: (i) => removed = i),
    );
    await tester.tap(find.byIcon(Icons.close).first, warnIfMissed: false);
    expect(removed, isNull);
  });

  testWidgets('画像のサムネイルをタップすると拡大表示が開き、外側タップで閉じる', (tester) async {
    await tester.pumpWidget(host(list: attachments));
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.byType(MediaViewerScreen), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(MediaViewerScreen), findsNothing);
  });

  testWidgets('動画のサムネイルをタップしても拡大は開かない', (tester) async {
    await tester.pumpWidget(host(list: attachments));
    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pumpAndSettle();
    expect(find.byType(MediaViewerScreen), findsNothing);
  });
}
