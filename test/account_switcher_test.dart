import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/profile_card.dart';
import 'package:daidai/models/profile_material.dart';
import 'package:daidai/models/saved_account.dart';
import 'package:daidai/repositories/auth_repository.dart';
import 'package:daidai/repositories/saved_accounts_store.dart';
import 'package:daidai/repositories/switch_session_repository.dart';
import 'package:daidai/services/account_switcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUser implements User {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.log);
  final List<String> log;

  @override
  Future<void> signOut() async => log.add('signOut');

  @override
  Future<User> signInWithCustomToken(String customToken) async {
    log.add('signIn:$customToken');
    return _FakeUser();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSessions implements SwitchSessionRepository {
  _FakeSessions(this.log);
  final List<String> log;
  bool revokeFails = false;
  SwitchAccountException? createFails;
  String nextUid = '';

  @override
  Future<({String ticket, int expiresAtMs})> createTicket() async {
    log.add('createTicket');
    return (ticket: 'T1', expiresAtMs: 5000);
  }

  @override
  Future<SavedAccount> createSession({
    String? ticket,
    String rhingSeed = '',
  }) async {
    log.add('createSession:${ticket ?? '-'}');
    if (createFails != null) throw createFails!;
    return SavedAccount(
      uid: nextUid,
      sessionId: 's-$nextUid',
      secret: 'sec-$nextUid',
      rhingSeed: rhingSeed,
    );
  }

  @override
  Future<String> redeem(SavedAccount account) async {
    log.add('redeem:${account.uid}');
    return 'token-${account.uid}';
  }

  @override
  Future<void> revoke(SavedAccount account) async {
    log.add('revoke:${account.uid}');
    if (revokeFails) {
      throw const SwitchAccountException(SwitchAccountFailure.other);
    }
  }
}

class _MemoryStore implements SavedAccountsStore {
  final accounts = <SavedAccount>[];
  PendingAccountAdd? pending;

  @override
  Future<List<SavedAccount>> load() async => List.of(accounts);

  @override
  Future<void> save(SavedAccount account) async {
    accounts
      ..removeWhere((a) => a.uid == account.uid)
      ..add(account);
  }

  @override
  Future<void> remove(String uid) async =>
      accounts.removeWhere((a) => a.uid == uid);

  @override
  Future<PendingAccountAdd?> loadPending() async => pending;

  @override
  Future<void> savePending(PendingAccountAdd p) async => pending = p;

  @override
  Future<void> clearPending() async => pending = null;
}

SavedAccount _saved(String uid) => SavedAccount(
  uid: uid,
  sessionId: 's-$uid',
  secret: 'sec-$uid',
  rhingSeed: uid,
);

AppUser _user(String uid) => AppUser(userId: uid, rhingSeed: uid);

void main() {
  late List<String> log;
  late _FakeSessions sessions;
  late _MemoryStore store;
  late AccountSwitcher switcher;
  var nowMs = 1000;

  setUp(() {
    log = [];
    nowMs = 1000;
    sessions = _FakeSessions(log);
    store = _MemoryStore();
    switcher = AccountSwitcher(
      sessions: sessions,
      store: store,
      auth: _FakeAuth(log),
      resetLocalState: () async => log.add('reset'),
      reloadPage: () => log.add('reload'),
      nowMs: () => nowMs,
    );
  });

  test('追加できるのは、今のアカウントと新しい1つを足して3つ以内の時だけ', () async {
    expect(await switcher.canAdd(_user('A')), isTrue); // 0件: A保存＋新しい1つ=2
    store.accounts.addAll([_saved('A'), _saved('B')]);
    expect(await switcher.canAdd(_user('A')), isTrue); // 2件: 新しい1つで3
    store.accounts.add(_saved('C'));
    expect(await switcher.canAdd(_user('A')), isFalse); // 3件: 満杯
    store.accounts
      ..clear()
      ..addAll([_saved('B'), _saved('C')]);
    expect(await switcher.canAdd(_user('A')), isFalse); // Aが未保存: 3+1で超える
  });

  test('追加の開始: 今のアカウントを保存し、チケットを保留にして、サインアウトする', () async {
    sessions.nextUid = 'A';
    await switcher.startAdd(_user('A'));
    expect(log, ['createSession:-', 'createTicket', 'signOut']);
    expect(store.accounts.map((a) => a.uid), ['A']);
    expect(store.pending?.ticket, 'T1');
    expect(store.pending?.fromUid, 'A');
  });

  test('標準のアイコンの写し: 保存済みのアカウントにだけ書き、変わらなければ書かない', () async {
    final user = AppUser(
      userId: 'A',
      rhingSeed: 'A',
      icons: const [
        ProfileMaterial(id: 'i1', url: 'https://x/i1', storagePath: 'p/i1'),
      ],
      activeIconId: 'i1',
    );
    expect(await switcher.refreshProfile(user), isFalse); // 未保存
    expect(store.accounts, isEmpty);
    store.accounts.add(_saved('A'));
    expect(await switcher.refreshProfile(user), isTrue);
    expect(store.accounts.single.iconUrl, 'https://x/i1');
    expect(await switcher.refreshProfile(user), isFalse); // 変化なし
  });

  test('保存したアカウントのJSON: アイコンの往復と、旧形式（アイコン無し）の読み込み', () {
    final a = _saved('A').withIcon('u', const ImageFocal(dx: .5, scale: 2));
    final back = SavedAccount.tryFromJson(a.toJson())!;
    expect(back.iconUrl, 'u');
    expect(back.iconFocal?.dx, .5);
    expect(back.iconFocal?.scale, 2);
    final old = SavedAccount.tryFromJson(_saved('B').toJson())!;
    expect(old.iconUrl, isNull);
    expect(old.iconFocal, isNull);
  });

  test('追加の開始: 既に保存済みなら自分用のセッションは作り直さない', () async {
    store.accounts.add(_saved('A'));
    await switcher.startAdd(_user('A'));
    expect(log, ['createTicket', 'signOut']);
  });

  test('追加の開始: 満杯なら何もせず上限のエラー', () async {
    store.accounts.addAll([_saved('A'), _saved('B'), _saved('C')]);
    await expectLater(
      switcher.startAdd(_user('A')),
      throwsA(
        isA<SwitchAccountException>().having(
          (e) => e.kind,
          'kind',
          SwitchAccountFailure.limitReached,
        ),
      ),
    );
    expect(log, isEmpty);
  });

  test('追加の完了: ログインしたアカウントを、チケットで保存し、保留を消す', () async {
    store.accounts.add(_saved('A'));
    store.pending = const PendingAccountAdd(
      ticket: 'T1',
      expiresAtMs: 5000,
      fromUid: 'A',
    );
    sessions.nextUid = 'B';
    expect(await switcher.completePendingAdd(_user('B')), isTrue);
    expect(log, ['createSession:T1']);
    expect(store.accounts.map((a) => a.uid).toSet(), {'A', 'B'});
    expect(store.pending, isNull);
  });

  test('追加の完了: 追加元と同じアカウント・期限切れ・保留なしは、保存せず保留も消す', () async {
    expect(await switcher.completePendingAdd(_user('B')), isFalse);

    store.pending = const PendingAccountAdd(
      ticket: 'T1',
      expiresAtMs: 5000,
      fromUid: 'A',
    );
    expect(await switcher.completePendingAdd(_user('A')), isFalse);
    expect(store.pending, isNull);

    store.pending = const PendingAccountAdd(
      ticket: 'T1',
      expiresAtMs: 500,
      fromUid: 'A',
    );
    expect(await switcher.completePendingAdd(_user('B')), isFalse);
    expect(store.pending, isNull);
    expect(log, isEmpty);
  });

  test('追加の完了: サーバーが拒否しても保留は消え、エラーが伝わる', () async {
    store.pending = const PendingAccountAdd(
      ticket: 'T1',
      expiresAtMs: 5000,
      fromUid: 'A',
    );
    sessions.createFails = const SwitchAccountException(
      SwitchAccountFailure.kiwamiRequired,
    );
    await expectLater(
      switcher.completePendingAdd(_user('B')),
      throwsA(isA<SwitchAccountException>()),
    );
    expect(store.pending, isNull);
    expect(store.accounts, isEmpty);
  });

  test('切り替え: 検証→サインイン→端末内の状態を消す→再読み込みの順', () async {
    await switcher.switchTo(_saved('B'));
    expect(log, ['redeem:B', 'signIn:token-B', 'reset', 'reload']);
  });

  test('切り替え: サーバーが拒否したら、サインインも再読み込みもしない', () async {
    final failing = AccountSwitcher(
      sessions: _RejectingSessions(),
      store: store,
      auth: _FakeAuth(log),
      resetLocalState: () async => log.add('reset'),
      reloadPage: () => log.add('reload'),
    );
    await expectLater(
      failing.switchTo(_saved('B')),
      throwsA(isA<SwitchAccountException>()),
    );
    expect(log, isEmpty);
  });

  test('取り外し: サーバーの失効に失敗しても、端末の保存は必ず消す', () async {
    store.accounts.addAll([_saved('A'), _saved('B')]);
    sessions.revokeFails = true;
    await switcher.forget('B');
    expect(log, ['revoke:B']);
    expect(store.accounts.map((a) => a.uid), ['A']);
  });
}

class _RejectingSessions extends _FakeSessions {
  _RejectingSessions() : super([]);

  @override
  Future<String> redeem(SavedAccount account) async {
    throw const SwitchAccountException(SwitchAccountFailure.kiwamiRequired);
  }
}
