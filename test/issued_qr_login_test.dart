import 'dart:async';

import 'package:daidai/features/auth/scan_qr_login_dialog.dart';
import 'package:daidai/features/settings/issue_qr_login_dialog.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/strings.dart';
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
import 'package:qr_flutter/qr_flutter.dart';

class _FakeAuth implements AuthRepository {
  final status = StreamController<String>.broadcast();
  final calls = <String>[];
  bool failRequest = false;

  @override
  Future<String> createIssuedQrLoginSession() async => 'sess1';

  @override
  Stream<String> watchQrLoginSessionStatus(String sessionId) => status.stream;

  @override
  Future<void> respondIssuedQrLogin(
    String sessionId, {
    required bool approve,
  }) async {
    calls.add('respond:$sessionId:$approve');
  }

  @override
  Future<void> requestIssuedQrLogin(String sessionId) async {
    if (failRequest) throw StateError('x');
    calls.add('request:$sessionId');
  }

  @override
  Future<User> claimQrLoginSession(String sessionId) async {
    calls.add('claim:$sessionId');
    // `User`は生成できないため、記録した上で失敗させる（ダイアログはエラー文言を出す）。
    throw StateError('no user in test');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _FakeAuth auth, Widget dialog) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
      ],
      child: MaterialApp(home: Scaffold(body: dialog)),
    ),
  );
  await _settle(tester);
}

final _ja = Strings.of(AppLocale.japanese);

/// 非同期の処理（Futureの完了・Streamの通知）を進めるため、少しずつ数回pumpする。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('QRを表示し、読み取り（requested）で許可を出し、許可でrespondを呼ぶ', (tester) async {
    final auth = _FakeAuth();
    addTearDown(auth.status.close);
    await _pump(tester, auth, const IssueQrLoginDialog());
    await _settle(tester);
    expect(find.byType(QrImageView), findsOneWidget);

    auth.status.add('requested');
    await _settle(tester);
    expect(find.text(_ja.qrIssueRequestTitle), findsOneWidget);
    expect(find.text(_ja.qrIssueAllow), findsOneWidget);

    await tester.tap(find.text(_ja.qrIssueAllow));
    await _settle(tester);
    expect(auth.calls, ['respond:sess1:true']);
  });

  testWidgets('拒否ではapprove=falseでrespondを呼ぶ', (tester) async {
    final auth = _FakeAuth();
    addTearDown(auth.status.close);
    await _pump(tester, auth, const IssueQrLoginDialog());
    await _settle(tester);
    auth.status.add('requested');
    await _settle(tester);
    await tester.tap(find.text(_ja.qrIssueDeny));
    await _settle(tester);
    expect(auth.calls, ['respond:sess1:false']);
  });

  testWidgets('ログイン側: 要求→approvedでclaimを呼ぶ', (tester) async {
    final auth = _FakeAuth();
    addTearDown(auth.status.close);
    await _pump(tester, auth, const ScanQrLoginDialog(sessionId: 'sess1'));
    await _settle(tester);
    expect(auth.calls, ['request:sess1']);
    expect(find.text(_ja.qrScanLoginWaitingMessage), findsOneWidget);

    auth.status.add('approved');
    await _settle(tester);
    await _settle(tester);
    expect(auth.calls, ['request:sess1', 'claim:sess1']);
    expect(find.text(_ja.qrLoginSignInError), findsOneWidget);
  });

  testWidgets('ログイン側: deniedで拒否の文言を出す', (tester) async {
    final denied = _FakeAuth();
    addTearDown(denied.status.close);
    await _pump(tester, denied, const ScanQrLoginDialog(sessionId: 's'));
    await _settle(tester);
    denied.status.add('denied');
    await _settle(tester);
    expect(find.text(_ja.qrScanLoginDenied), findsOneWidget);
  });

  testWidgets('ログイン側: 要求に失敗したらエラー文言を出す', (tester) async {
    final failing = _FakeAuth()..failRequest = true;
    addTearDown(failing.status.close);
    await _pump(tester, failing, const ScanQrLoginDialog(sessionId: 's'));
    await _settle(tester);
    await _settle(tester);
    expect(find.text(_ja.qrScanLoginRequestError), findsOneWidget);
  });
}
