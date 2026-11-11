import '../models/app_user.dart';
import '../models/profile_card.dart';
import '../models/saved_account.dart';
import '../repositories/auth_repository.dart';
import '../repositories/saved_accounts_store.dart';
import '../repositories/switch_session_repository.dart';

/// 複数アカウントの切り替え（2026-11-11、極みの特典）の流れをまとめたもの。設計は
/// `文書/複数アカウント.md`。極みの判定はサーバー（`createSwitchTicket`・
/// `createSwitchSession`・`redeemSwitchSession`）が行い、ここは端末の保存と流れだけを持つ。
class AccountSwitcher {
  AccountSwitcher({
    required this.sessions,
    required this.store,
    required this.auth,
    required this.resetLocalState,
    required this.reloadPage,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final SwitchSessionRepository sessions;
  final SavedAccountsStore store;
  final AuthRepository auth;

  /// 前のアカウントの端末内の状態を消す（`clearAccountBoundLocalState`）。
  final Future<void> Function() resetLocalState;

  /// アプリ全体の状態を作り直す再読み込み（Webのみ）。
  final void Function() reloadPage;

  final int Function() _nowMs;

  /// 1つの端末に保存できるアカウントの数（今のアカウントを含む）。
  static const maxAccounts = 3;

  Future<List<SavedAccount>> accounts() => store.load();

  /// 追加できるか（今のアカウントの保存分と、新しい1つの余地があるか）。
  Future<bool> canAdd(AppUser current) async {
    final saved = await store.load();
    final currentSaved = saved.any((a) => a.uid == current.userId);
    return saved.length + (currentSaved ? 0 : 1) + 1 <= maxAccounts;
  }

  /// アカウントの追加を始める。今のアカウントを保存し（まだなら）、追加チケットを持って
  /// サインアウトする。サインアウトの後は、ログイン画面で別のアカウントにログインし、
  /// [completePendingAdd]で保存する。通知のトークンは解除しない（他のアカウントの
  /// 通知も届くように）。サーバーが極みでないと拒否する。
  Future<void> startAdd(AppUser current) async {
    if (!await canAdd(current)) {
      throw const SwitchAccountException(SwitchAccountFailure.limitReached);
    }
    final saved = await store.load();
    if (!saved.any((a) => a.uid == current.userId)) {
      final own = await sessions.createSession(rhingSeed: current.rhingSeed);
      await store.save(_withIconOf(own, current));
    }
    final ticket = await sessions.createTicket();
    await store.savePending(
      PendingAccountAdd(
        ticket: ticket.ticket,
        expiresAtMs: ticket.expiresAtMs,
        fromUid: current.userId,
      ),
    );
    await auth.signOut();
  }

  /// 追加の途中でログインした直後に呼ぶ。保留中の追加があれば、ログインしたアカウントの
  /// 合言葉を作って保存する。保留はここで必ず消す（失敗しても繰り返さない）。保存したら
  /// `true`。保留が無い・期限切れ・追加元と同じアカウントなら`false`。
  Future<bool> completePendingAdd(AppUser user) async {
    final pending = await store.loadPending();
    if (pending == null) return false;
    await store.clearPending();
    if (pending.expiresAtMs < _nowMs()) return false;
    if (pending.fromUid == user.userId) return false;
    final saved = await store.load();
    if (saved.any((a) => a.uid == user.userId)) return false;
    if (saved.length >= maxAccounts) {
      throw const SwitchAccountException(SwitchAccountFailure.limitReached);
    }
    final account = await sessions.createSession(
      ticket: pending.ticket,
      rhingSeed: user.rhingSeed,
    );
    await store.save(_withIconOf(account, user));
    return true;
  }

  SavedAccount _withIconOf(SavedAccount account, AppUser user) => account
      .withIcon(user.effectiveIcon?.url, user.effectiveIconFocalFor(null));

  /// 保存済みの[user]のアカウントに、今の標準のアイコンを写す。保存が無い・変わって
  /// いなければ何もしない。
  Future<bool> refreshProfile(AppUser user) async {
    final saved = await store.load();
    final index = saved.indexWhere((a) => a.uid == user.userId);
    if (index < 0) return false;
    final old = saved[index];
    final url = user.effectiveIcon?.url;
    final focal = user.effectiveIconFocalFor(null);
    if (old.iconUrl == url && _sameFocal(old.iconFocal, focal)) return false;
    await store.save(old.withIcon(url, focal));
    return true;
  }

  static bool _sameFocal(ImageFocal? a, ImageFocal? b) =>
      (a?.dx ?? 0) == (b?.dx ?? 0) &&
      (a?.dy ?? 0) == (b?.dy ?? 0) &&
      (a?.scale ?? 1) == (b?.scale ?? 1);

  /// 追加を途中でやめた時のために、保留の追加を捨てる。
  Future<void> cancelPendingAdd() => store.clearPending();

  Future<bool> hasPendingAdd() async {
    final pending = await store.loadPending();
    return pending != null && pending.expiresAtMs >= _nowMs();
  }

  /// [account]へ切り替える。サーバーで検証し、カスタムトークンでサインインし、
  /// 前のアカウントの端末内の状態を消して、ページを再読み込みする。
  Future<void> switchTo(SavedAccount account) async {
    final token = await sessions.redeem(account);
    await auth.signInWithCustomToken(token);
    await resetLocalState();
    // サインイン状態の保存が終わる前に再読み込みしないよう、少し待つ。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    reloadPage();
  }

  /// この端末から[uid]のアカウントの保存を消す（取り外し・ログアウト）。サーバーの
  /// 合言葉も失効させるが、通信に失敗しても端末の保存は必ず消す。
  Future<void> forget(String uid) async {
    final saved = await store.load();
    for (final account in saved.where((a) => a.uid == uid)) {
      try {
        await sessions.revoke(account);
      } on SwitchAccountException {
        // サーバー側は期限（90日）で失効する。端末の保存だけは消す。
      }
    }
    await store.remove(uid);
  }
}
