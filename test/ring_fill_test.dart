import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/features/chat/talks_tab.dart' show CategoryTab;
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
import 'package:daidai/widgets/liquid_tile_group.dart';
import 'package:daidai/widgets/ring_list_scope.dart';

/// 囲みの一覧で、選択中の項目の背面を塗り潰し、文字を塗りの反対色にする（2026-11-27）。劇画も、
/// 囲みの時は、大きな箱の中で、選択中の項目を白い箱（文字は黒）で囲む。
Color? _textColor(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  return paragraph.text.style?.color;
}

Widget _app(AppUiStyle style, Widget child) => ProviderScope(
  overrides: [
    initialAppUiStyleProvider.overrideWithValue(style),
    initialAccentColorProvider.overrideWithValue(const Color(0xFF3D2EE0)),
    initialSelectionMotionProvider.overrideWithValue(SelectionMotion.ring),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 300, height: 400, child: child),
      ),
    ),
  ),
);

void main() {
  for (final style in [
    AppUiStyle.gekiga,
    AppUiStyle.flat,
    AppUiStyle.block,
    AppUiStyle.chalk,
    AppUiStyle.kinari,
    AppUiStyle.glass,
  ]) {
    testWidgets('囲みの一覧（目印の枠）: 選択中の背面を塗り潰す（$style）', (tester) async {
      await tester.pumpWidget(
        _app(
          style,
          RingListBlock(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (var k = 0; k < 3; k++)
                  Builder(
                    builder: (context) {
                      final tile = ListTile(title: Text('項目$k'));
                      final s = RingListScope.styleOf(context)!;
                      return k == 1
                          ? RingSelectedMarker(style: s, child: tile)
                          : tile;
                    },
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 塗りの面が有る。
      expect(find.byType(RingFill), findsWidgets);
      final context = tester.element(find.text('項目1'));
      final onPrimary =
          RingOnPrimary.colorFor(style) ??
          Theme.of(context).colorScheme.onPrimary;
      final unselected = _textColor(tester, '項目0');
      final selected = _textColor(tester, '項目1');
      if (ringNeedsOnPrimary(style)) {
        // 選択中だけ、塗りの反対色になる。
        expect(selected, onPrimary);
        expect(unselected, isNot(onPrimary));
      } else {
        // ガラスは、選択色の上でも、文字の色を変えない。
        expect(selected, unselected);
      }
    });

    testWidgets('囲みの一覧（項目グループ）: 選択中の背面を塗り潰す（$style）', (tester) async {
      await tester.pumpWidget(
        _app(
          style,
          LiquidTileGroup(
            itemCount: 3,
            selectedIndex: 1,
            child: ListView(
              children: [
                for (var k = 0; k < 3; k++)
                  LiquidTile(
                    index: k,
                    builder: (context, sel) => ListTile(title: Text('項目$k')),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RingFill), findsWidgets);
      final context = tester.element(find.text('項目1'));
      final onPrimary =
          RingOnPrimary.colorFor(style) ??
          Theme.of(context).colorScheme.onPrimary;
      if (ringNeedsOnPrimary(style)) {
        expect(_textColor(tester, '項目1'), onPrimary);
        expect(_textColor(tester, '項目0'), isNot(onPrimary));
      } else {
        expect(_textColor(tester, '項目1'), _textColor(tester, '項目0'));
      }
    });
  }

  // 一対・広場のトグル（[CategoryTab]）は、文字色を、ビルダーに渡される`context`の`Theme`で決める。
  // 囲みで塗り潰された選択中のトグルが、白い塗りに白い文字にならないこと（2026-11-27）。
  for (final style in AppUiStyle.values) {
    testWidgets('囲みの一対・広場のトグル: 選択中の文字は、塗りの反対色（$style）', (tester) async {
      await tester.pumpWidget(
        _app(
          style,
          LiquidTileGroup(
            itemCount: 2,
            selectedIndex: 0,
            child: Row(
              children: [
                CategoryTab(
                  liquidIndex: 0,
                  label: '一対',
                  count: 8,
                  selected: true,
                  onTap: () {},
                ),
                CategoryTab(
                  liquidIndex: 1,
                  label: '広場',
                  count: 4,
                  selected: false,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.text('一対 8'));
      final onPrimary =
          RingOnPrimary.colorFor(style) ??
          Theme.of(context).colorScheme.onPrimary;
      if (ringNeedsOnPrimary(style)) {
        expect(_textColor(tester, '一対 8'), onPrimary);
        expect(_textColor(tester, '広場 4'), isNot(onPrimary));
      } else {
        expect(_textColor(tester, '一対 8'), _textColor(tester, '広場 4'));
      }
    });
  }
}
