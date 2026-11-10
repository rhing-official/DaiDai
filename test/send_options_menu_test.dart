import 'package:daidai/features/chat/scheduled_send_ui.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/strings.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final style in [AppUiStyle.flat, AppUiStyle.gekiga, AppUiStyle.block]) {
    testWidgets('送信ボタン長押し→押したまま項目へなぞって離すと選べる（$style）', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SendOptionsMenuHandle? menu;
      SendOptionChoice? chosen;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
            initialAppUiStyleProvider.overrideWithValue(style),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomRight,
                child: Builder(
                  builder: (context) => RawGestureDetector(
                    gestures: {
                      LongPressGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            LongPressGestureRecognizer
                          >(
                            () => LongPressGestureRecognizer(
                              duration: const Duration(milliseconds: 250),
                            ),
                            (r) {
                              r.onLongPress = () {
                                final box =
                                    context.findRenderObject()! as RenderBox;
                                final strings = ProviderScope.containerOf(
                                  context,
                                ).read(appStringsProvider);
                                menu = showSendOptionsMenu(
                                  context: context,
                                  strings: strings,
                                  anchorBox: box,
                                );
                                menu!.result.then((v) => chosen = v);
                              };
                              r.onLongPressMoveUpdate = (d) {
                                menu?.update(d.globalPosition);
                              };
                              r.onLongPressEnd = (d) {
                                menu?.release(d.globalPosition);
                              };
                            },
                          ),
                    },
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.send),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final button = tester.getCenter(find.byIcon(Icons.send));
      final gesture = await tester.startGesture(button);
      await tester.pump(const Duration(milliseconds: 300));
      expect(menu, isNotNull);
      // 1つ目の項目（通知なしで送信）へなぞる。
      final target = tester.getCenter(find.text('通知なしで送信'));
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(chosen, SendOptionChoice.silent);
    });
  }
}
