import 'package:daidai/features/auth/passcode_lock_screen.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/strings.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/passcode_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePasscode implements PasscodeRepository {
  @override
  Future<bool> isBiometricEnabled() async => false;

  @override
  Future<bool> canUseBiometrics() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // 「サインアウトしてリセット」が長くても、狭い画面で縦積みにならず、
  // キャンセルがいつも左（2026-11-09）。
  for (final size in [const Size(1400, 900), const Size(390, 800)]) {
    for (final locale in [
      AppLocale.japanese,
      AppLocale.britishEnglish,
      AppLocale.french,
    ]) {
      for (final style in [AppUiStyle.flat, AppUiStyle.glass]) {
        testWidgets('キャンセルは「リセット」の左: $size $locale $style', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final strings = Strings.of(locale);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                passcodeRepositoryProvider.overrideWithValue(_FakePasscode()),
                initialAppLocaleProvider.overrideWithValue(locale),
                initialAppUiStyleProvider.overrideWithValue(style),
                initialAccentColorProvider.overrideWithValue(
                  const Color(0xFFF08300),
                ),
              ],
              child: const MaterialApp(home: PasscodeLockScreen()),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(strings.passcodeLockScreenForgotButton));
          await tester.pumpAndSettle();

          final cancel = tester.getRect(find.text(strings.cancel));
          final confirm = tester.getRect(
            find.text(strings.passcodeForgotDialogConfirmButton),
          );
          expect(cancel.right, lessThanOrEqualTo(confirm.left));
          // 広い画面では本文も1行に収まる幅（折り返さない）。
          if (size.width > 1000) {
            expect(
              tester
                  .getSize(find.text(strings.passcodeForgotDialogMessage))
                  .width,
              greaterThan(480),
            );
          }
          // 同じ行（縦に重ならない配置＝縦積みでない）。
          expect((cancel.center.dy - confirm.center.dy).abs(), lessThan(30));
          // ボタンの文字が折り返されない（1行の高さに収まる）。
          if (size.width > 1000) {
            expect(cancel.height, lessThan(24));
            // 日本語は「サインアウト」の後で意図的に改行する（2行）。
            if (locale != AppLocale.japanese) {
              expect(confirm.height, lessThan(24));
            }
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
