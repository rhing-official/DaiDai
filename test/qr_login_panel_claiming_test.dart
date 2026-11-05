import 'dart:async';

import 'package:daidai/features/auth/qr_login_panel.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth implements AuthRepository {
  final status = StreamController<String>.broadcast();
  final claim = Completer<User>();

  @override
  Future<String> createQrLoginSession() async => 'sess1';

  @override
  Stream<String> watchQrLoginSessionStatus(String sessionId) => status.stream;

  @override
  Future<User> claimQrLoginSession(String sessionId) => claim.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('承認後のログイン処理中はQRコードにくるくるを出し、失敗すると消える', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
          initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
        ],
        child: const MaterialApp(home: Scaffold(body: QrLoginPanel())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    auth.status.add('approved');
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    auth.claim.completeError(StateError('x'));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
