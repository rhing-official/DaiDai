import 'dart:async';

import 'package:daidai/features/auth/auth_gate.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/saved_account.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/account_switcher_providers.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/auth_repository.dart';
import 'package:daidai/repositories/saved_accounts_store.dart';
import 'package:daidai/repositories/switch_session_repository.dart';
import 'package:daidai/repositories/user_repository.dart';
import 'package:daidai/services/account_switcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// アカウントの追加の途中でアプリを再起動した時に、作成の画面に閉じ込めず、元のアカウントへ
/// 自動で戻す（2026-11-18）。

class _FakeUser implements User {
  _FakeUser(this.uid);
  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.log, this.uid);
  final List<String> log;
  final String uid;

  @override
  Stream<User?> authStateChanges() => Stream.value(_FakeUser(uid));

  @override
  Future<void> signOut() async => log.add('signOut');

  @override
  Future<User> signInWithCustomToken(String customToken) async {
    log.add('signIn:$customToken');
    return _FakeUser(uid);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 住人データの取得は、ずっと待たせる（この試験で見るのは、その手前の復帰だけ）。
class _NeverUsers implements UserRepository {
  @override
  Future<AppUser?> getUser(String userId) => Completer<AppUser?>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sessions implements SwitchSessionRepository {
  _Sessions(this.log);
  final List<String> log;

  @override
  Future<String> redeem(SavedAccount account) async {
    log.add('redeem:${account.uid}');
    return 'token-${account.uid}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements SavedAccountsStore {
  final accounts = <SavedAccount>[];
  PendingAccountAdd? pending;

  @override
  Future<List<SavedAccount>> load() async => List.of(accounts);

  @override
  Future<PendingAccountAdd?> loadPending() async => pending;

  @override
  Future<void> savePending(PendingAccountAdd p) async => pending = p;

  @override
  Future<void> clearPending() async => pending = null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Started extends AddStartedThisSessionNotifier {
  @override
  bool build() => true;
}

SavedAccount _saved(String uid) =>
    SavedAccount(uid: uid, sessionId: 's', secret: 'x', rhingSeed: uid);

PendingAccountAdd _pending({bool continued = false}) => PendingAccountAdd(
  ticket: 'T',
  expiresAtMs: 99999,
  fromUid: 'A',
  continued: continued,
);

Future<void> _pump(
  WidgetTester tester, {
  required _Store store,
  required List<String> log,
  bool addStarted = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final switcher = AccountSwitcher(
    sessions: _Sessions(log),
    store: store,
    auth: _FakeAuth(log, 'A'),
    resetLocalState: (_) async {
      log.add('reset');
      return true;
    },
    reloadPage: () => log.add('reload'),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // 新しいアカウントB（作成の途中）でログインして起動した。
        authRepositoryProvider.overrideWithValue(_FakeAuth(log, 'B')),
        accountSwitcherProvider.overrideWithValue(switcher),
        userRepositoryProvider.overrideWithValue(_NeverUsers()),
        if (addStarted)
          addStartedThisSessionProvider.overrideWith(_Started.new),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAccentColorProvider.overrideWithValue(kDefaultAccentColor),
      ],
      child: MaterialApp(home: AuthGate(builder: (_, _) => const SizedBox())),
    ),
  );
  // スピナー・スケルトンは終わらないので、`pumpAndSettle`は使わない。
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('追加の途中で再起動した（新しいアカウントでログイン中）なら、元のアカウントへ戻す', (tester) async {
    final log = <String>[];
    final store = _Store()
      ..accounts.add(_saved('A'))
      ..pending = _pending();
    await _pump(tester, store: store, log: log);
    expect(log, containsAllInOrder(['redeem:A', 'signIn:token-A', 'reload']));
    expect(log, isNot(contains('signOut')));
    expect(store.pending, isNull);
  });

  testWidgets('元のアカウントへ戻せなかったら、作りかけのアカウントをサインアウトしてログイン画面へ出す', (tester) async {
    final log = <String>[];
    // 追加元の保存が無い。
    final store = _Store()..pending = _pending();
    await _pump(tester, store: store, log: log);
    expect(log, contains('signOut'));
    expect(log, isNot(contains('reload')));
  });

  testWidgets('このセッションで追加を始めた時は、戻さない', (tester) async {
    final log = <String>[];
    final store = _Store()
      ..accounts.add(_saved('A'))
      ..pending = _pending();
    await _pump(tester, store: store, log: log, addStarted: true);
    expect(log, isNot(contains('redeem:A')));
    expect(log, isNot(contains('signOut')));
    expect(store.pending, isNotNull);
  });

  testWidgets('設定の入れ替えによる再読み込みの後の起動は、再起動ではないので戻さず、印を消す', (tester) async {
    final log = <String>[];
    final store = _Store()
      ..accounts.add(_saved('A'))
      ..pending = _pending(continued: true);
    await _pump(tester, store: store, log: log);
    expect(log, isNot(contains('redeem:A')));
    expect(log, isNot(contains('signOut')));
    expect(store.pending, isNotNull);
    expect(store.pending!.continued, isFalse);
  });

  testWidgets('保留が無ければ、何もしない', (tester) async {
    final log = <String>[];
    final store = _Store()..accounts.add(_saved('A'));
    await _pump(tester, store: store, log: log);
    expect(log, isEmpty);
  });
}
