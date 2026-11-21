import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/chat/sticker_suggestion_strip.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/sticker.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';

const _stickers = [
  Sticker(stickerId: 'a', name: 'a', imageUrl: 'http://invalid.test/a.png'),
  Sticker(stickerId: 'b', name: 'b', imageUrl: 'http://invalid.test/b.png'),
  Sticker(stickerId: 'c', name: 'c', imageUrl: 'http://invalid.test/c.png'),
];

Widget _host({
  required int? previewIndex,
  required void Function(int) onIndex,
  required void Function(Sticker) onSend,
}) {
  return ProviderScope(
    overrides: [initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat)],
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 420,
            child: StickerSuggestionStrip(
              stickers: _stickers,
              onStickerTap: (_) {},
              previewIndex: previewIndex,
              onPreviewIndexChanged: onIndex,
              onPreviewSend: onSend,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('横スワイプで隣の候補へ切り替わる', (tester) async {
    final indexes = <int>[];
    await tester.pumpWidget(
      _host(previewIndex: 1, onIndex: indexes.add, onSend: (_) {}),
    );
    await tester.pumpAndSettle();
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(indexes, isNotEmpty);
    expect(indexes.last, 2);
  });

  testWidgets('中央のぺったんのタップで送信される', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      _host(
        previewIndex: 1,
        onIndex: (_) {},
        onSend: (s) => sent.add(s.stickerId),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    expect(sent, ['b']);
  });

  testWidgets('拡大していない時は拡大表示が無い', (tester) async {
    await tester.pumpWidget(
      _host(previewIndex: null, onIndex: (_) {}, onSend: (_) {}),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('ホイール（スクロール）で隣の候補へ切り替わる', (tester) async {
    final indexes = <int>[];
    await tester.pumpWidget(
      _host(previewIndex: 1, onIndex: indexes.add, onSend: (_) {}),
    );
    await tester.pumpAndSettle();
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(PageView))),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pumpAndSettle();
    expect(indexes, isNotEmpty);
    expect(indexes.last, 2);
  });
}
