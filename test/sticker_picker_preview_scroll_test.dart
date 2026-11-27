import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daidai/features/chat/sticker_picker_content.dart';
import 'package:daidai/features/chat/sticker_picker_popup.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/sticker.dart';
import 'package:daidai/models/sticker_send_mode.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/owned_sticker_packs_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/providers/sticker_send_mode_provider.dart';

class _FakeUser extends Fake implements User {
  @override
  String get uid => 'u1';
}

class _Result {
  bool value = false;
  Sticker? picked;
}

const _stickers = [
  Sticker(stickerId: 'a', name: 'a', imageUrl: 'http://invalid.test/a.png'),
  Sticker(stickerId: 'b', name: 'b', imageUrl: 'http://invalid.test/b.png'),
  Sticker(stickerId: 'c', name: 'c', imageUrl: 'http://invalid.test/c.png'),
];

void main() {
  testWidgets('拡大プレビューの上のホイールで隣のぺったんへ切り替わる', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sent = <String>[];
    await tester.binding.setSurfaceSize(const Size(900, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialStickerSendModeProvider.overrideWithValue(
            StickerSendMode.line,
          ),
          authStateProvider.overrideWith((ref) => Stream.value(_FakeUser())),
          ownedStickerPacksProvider('u1').overrideWith(
            (ref) => Stream.value(const [
              StickerPack(
                packId: 'p',
                creatorId: 'c',
                name: 'p',
                price: 0,
                stickers: _stickers,
                category: '',
                tags: [],
                salesCount: 0,
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 360,
                height: 420,
                child: StickerPickerContent(
                  railAxis: Axis.vertical,
                  onStickerSelected: (s) => sent.add(s.stickerId),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 一覧の最初のぺったん（a）をタップして拡大プレビューを出す。
    final firstTile = find
        .descendant(of: find.byType(GridView), matching: find.byType(InkWell))
        .first;
    await tester.tap(firstTile);
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);

    // プレビューの上でホイールを回す。
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(PageView))),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pumpAndSettle();
    // 提案パネルの拡大と同じカルーセル。隣へ寄ったらページが切り替わっている。
    expect(find.byType(PageView), findsOneWidget);
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller;
    expect(controller!.page, closeTo(1, 0.01));
    expect(sent, isEmpty);
  });

  // ぺったんボタンから出すPCのポップアップ（OverlayEntry）の流れで、拡大プレビューの
  // 切り替え・送信・外側クリックで閉じる、がエラー無く動く。
  // 無限に動くアニメーションがあっても止まらないよう、一定回数だけ時間を進める。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<_Result> openPopup(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    final result = _Result();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialStickerSendModeProvider.overrideWithValue(
            StickerSendMode.line,
          ),
          authStateProvider.overrideWith((ref) => Stream.value(_FakeUser())),
          ownedStickerPacksProvider('u1').overrideWith(
            (ref) => Stream.value(const [
              StickerPack(
                packId: 'p',
                creatorId: 'c',
                name: 'p',
                price: 0,
                stickers: _stickers,
                category: '',
                tags: [],
                salesCount: 0,
              ),
              StickerPack(
                packId: 'q',
                creatorId: 'c',
                name: 'q',
                price: 0,
                stickers: [
                  Sticker(
                    stickerId: 'd',
                    name: 'd',
                    imageUrl: 'http://invalid.test/d.png',
                  ),
                ],
                category: '',
                tags: [],
                salesCount: 0,
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Align(
                alignment: Alignment.bottomRight,
                child: TextButton(
                  onPressed: () {
                    showStickerPickerPopup(
                      context,
                      anchorRect: const Rect.fromLTWH(1000, 800, 40, 40),
                    ).then((picked) {
                      result.value = true;
                      result.picked = picked;
                    });
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    return result;
  }

  testWidgets('ポップアップ: 拡大→ホイール→中央タップで送信してもエラーが出ない', (tester) async {
    final done = await openPopup(tester);
    await tester.tap(
      find
          .descendant(of: find.byType(GridView), matching: find.byType(InkWell))
          .first,
    );
    await settle(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(PageView))),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await settle(tester);
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await settle(tester);
    await settle(tester);
    expect(done.value, isTrue);
    expect(done.picked?.stickerId, 'b');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ポップアップ: 拡大中に外側をクリックして閉じてもエラーが出ない', (tester) async {
    final done = await openPopup(tester);
    await tester.tap(
      find
          .descendant(of: find.byType(GridView), matching: find.byType(InkWell))
          .first,
    );
    await settle(tester);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    await settle(tester);
    expect(done.value, isTrue);
    expect(done.picked, isNull);
    // ポップアップと一緒に、拡大表示も閉じている。
    expect(find.byType(PageView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  Finder gridTiles() => find.descendant(
    of: find.byType(GridView),
    matching: find.byType(InkWell),
  );

  testWidgets('ポップアップ: 別のぺったんを開いたら拡大表示が閉じる', (tester) async {
    await openPopup(tester);
    await tester.tap(gridTiles().first);
    await settle(tester);
    expect(find.byType(PageView), findsOneWidget);

    // 左のレールの、最後のぺったんのアイコンを押す。
    await tester.tap(
      find
          .descendant(of: find.byType(ListView), matching: find.byType(InkWell))
          .last,
    );
    await settle(tester);
    expect(find.byType(PageView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ポップアップ: ぺったん以外（検索欄）をクリックしたら拡大表示が閉じる', (tester) async {
    await openPopup(tester);
    await tester.tap(gridTiles().first);
    await settle(tester);
    expect(find.byType(PageView), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await settle(tester);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('ポップアップ: 別のぺったん自体のタップでは閉じず、切り替わる', (tester) async {
    await openPopup(tester);
    await tester.tap(gridTiles().first);
    await settle(tester);
    expect(find.byType(PageView), findsOneWidget);

    await tester.tap(gridTiles().at(1));
    await settle(tester);
    expect(find.byType(PageView), findsOneWidget);
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller;
    expect(controller!.page, closeTo(1, 0.01));
  });
}
