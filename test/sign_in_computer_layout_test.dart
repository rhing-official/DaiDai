import 'dart:async';

import 'package:daidai/features/auth/qr_login_panel.dart';
import 'package:daidai/features/auth/sign_in_screen.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/auth_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _FakeAuth implements AuthRepository {
  @override
  Future<String> createQrLoginSession() async => 'q1';

  @override
  Stream<String> watchQrLoginSessionStatus(String sessionId) =>
      const Stream<String>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuth()),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
      ],
      child: const MaterialApp(home: SignInScreen()),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets(
    'コンピューターの広い画面では、右にQRコードを出す2列になる',
    (tester) async {
      await _pump(tester, const Size(1100, 800));
      expect(find.byType(QrLoginPanel), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    '幅が狭い・モバイルでは従来の1列（QRはボタンから）',
    (tester) async {
      await _pump(tester, const Size(500, 900));
      expect(find.byType(QrLoginPanel), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
