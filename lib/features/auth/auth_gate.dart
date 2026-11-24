import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/saved_account.dart';
import '../../models/app_user.dart';
import '../../models/residence.dart';
import '../../providers/account_switcher_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_preferences_sync.dart';
import '../../utils/account_local_state.dart';
import '../../utils/page_reload/page_reload.dart';
import 'account_restore_screen.dart';
import 'restore_original_account.dart';
import '../guide/first_run_tutorial_screen.dart';
import '../setup/initial_setup_screen.dart';
import 'account_suspended_screen.dart';
import 'passcode_lock_gate.dart';
import 'residence_survey_screen.dart';
import 'rhing_seed_setup_screen.dart';
import 'sign_in_screen.dart';
import 'terms_consent_screen.dart';
import '../../widgets/delayed_spinner.dart';
import '../../widgets/home_skeleton.dart';

/// 認証状態・Rhing Seed登録状態に応じて表示を切り替える汎用ゲート。
/// ログイン済み・Rhing Seed登録済みになった時点で[builder]を呼ぶ。
/// [AppGate]（アプリのルート画面）と、招待リンク（`/invite/:rhingSeed`）など
/// 未ログインでも開かれうる入り口の両方から使う。
class AuthGate extends ConsumerWidget {
  const AuthGate({required this.builder, super.key});

  final Widget Function(BuildContext context, AppUser currentUser) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const Scaffold(body: DelayedSpinner()),
      error: (error, _) => Scaffold(
        body: Center(
          child: Text(
            ref.read(appStringsProvider).authGateErrorTemplate(error),
          ),
        ),
      ),
      data: (user) {
        if (user == null) {
          return const _SignInGate();
        }
        return _AuthenticatedUserGate(userId: user.uid, builder: builder);
      },
    );
  }
}

class _AuthenticatedUserGate extends ConsumerStatefulWidget {
  const _AuthenticatedUserGate({required this.userId, required this.builder});

  final String userId;
  final Widget Function(BuildContext context, AppUser currentUser) builder;

  @override
  ConsumerState<_AuthenticatedUserGate> createState() =>
      _AuthenticatedUserGateState();
}

class _AuthenticatedUserGateState
    extends ConsumerState<_AuthenticatedUserGate> {
  late Future<({AppUser? user, Residence? residence, bool isAdmin})> _future;

  /// 新規アカウント作成時、[RhingSeedSetupScreen]の前に[TermsConsentScreen]で
  /// 同意したかどうか（このセッション内のみの一時的な状態、2026-09-14追加）。
  bool _termsAgreed = false;

  /// 初回の使い方ガイドを（スキップ含め）終えたか（このセッション内のみ、
  /// 2026-10-17追加）。視聴記録の書き込みに失敗してもガイドが出続けないよう、
  /// Firestore側の値とは別に持つ。
  bool _guideDone = false;

  /// 初期設定（[InitialSetupScreen]）を終えたか。
  bool _setupDone = false;

  /// 追加の途中で終わったままの起動かを、もう調べたか（2026-11-18、最初の1回だけ）。
  bool _leftoverChecked = false;

  @override
  void initState() {
    super.initState();
    _future = _fetchUser();
  }

  // 端末をまたいで同期する表示設定（アクセントカラー・外観・表示言語等）を、
  // ログイン直後に一度だけFirestoreの値で上書きする（[applyRemoteUserPreferences]）。
  // アカウント復元後にユーザーを再取得する際も同じ処理でよい為、
  // [AccountRestoreScreen.onRestored]からも呼び直す。
  Future<({AppUser? user, Residence? residence, bool isAdmin})>
  _fetchUser() async {
    // アカウントの追加の途中で終わったまま（アプリの再起動・ページの再読み込み）、新しい
    // アカウントでログインして起動した時は、作成の画面（規約・Rhing Seed・居住地アンケート・
    // 初期設定・使い方ガイド）に閉じ込めず、元のアカウントへ自動で戻す（2026-11-18）。
    // このセッションで追加を始めた時は対象外。端末の設定の入れ替えによる再読み込みを
    // 挟んだ起動は、`takeLeftoverAdd`が見分ける。
    if (!_leftoverChecked) {
      _leftoverChecked = true;
      if (!ref.read(addStartedThisSessionProvider) &&
          await ref
              .read(accountSwitcherProvider)
              .takeLeftoverAdd(currentUid: widget.userId)) {
        await _restoreLeftoverAdd();
        // 戻す（再読み込み）か、ログイン画面へ出る（サインアウト）まで待つ。
        await Completer<void>().future;
      }
    }
    // 端末の設定は、ログインしたアカウントのものへ入れ替える（前のアカウントの設定は退避、
    // 2026-11-14）。入れ替わった時は、設定を読み直すためアプリを作り直す。
    if (await swapLocalStateTo(widget.userId)) {
      // 追加の途中なら、この再読み込みは再起動ではないと、次の起動に伝える。
      await ref.read(accountSwitcherProvider).markAddContinues();
      reloadPage();
      // 作り直されるまで待つ（この画面は破棄される）。
      await Completer<void>().future;
    }
    final user = await ref.read(userRepositoryProvider).getUser(widget.userId);
    if (user == null) return (user: null, residence: null, isAdmin: false);
    applyRemoteUserPreferences(ref, user.preferences);
    // 最終ログイン日時（管理画面向け）。自動ログインでの再開時も含めて
    // 認証済みセッションを確認するたびに更新する。結果を待つ必要は
    // 無いためawaitしない。
    ref.read(userRepositoryProvider).touchLastLogin(user.userId);
    // 居住地アンケートの回答有無（2026-10-16追加）。取得に失敗した場合は
    // 「未回答」と誤判定して回答済みの住人にアンケートを出し直さないよう、
    // 例外のまま呼び出し元（再試行可能なエラー画面）へ伝える。
    final residence = await ref
        .read(residenceRepositoryProvider)
        .getResidence(user.userId);
    // 管理者（運営者）のアカウントからは居住地を集めない（2026-10-18追加）。
    final isAdmin = await ref.read(authRepositoryProvider).isAdmin();
    return (user: user, residence: residence, isAdmin: isAdmin);
  }

  /// 途中で終わった追加を、元のアカウントへ戻す。戻せなかった時（追加元の保存が無い・
  /// 失効・通信不可）は、作りかけのアカウントに閉じ込めないため、サインアウトして通常の
  /// ログイン画面へ出す。作りかけのアカウントは、次にログインすれば続きから作れる。
  Future<void> _restoreLeftoverAdd() async {
    // 最初のフレームの後（バナーを出せるOverlayができてから）に呼ぶ。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final restored = await restoreOriginalAccount(context, ref);
    if (!restored && mounted) {
      await ref.read(authRepositoryProvider).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({AppUser? user, Residence? residence, bool isAdmin})>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // アカウントの追加の途中でログインした直後は、読み込みが進んでいることが分かる
          // ようにスケルトンを出す（2026-11-12）。それ以外は従来のスピナー。
          final adding = ref.watch(hasPendingAccountAddProvider).value ?? false;
          return adding
              ? const HomeSkeleton()
              : const Scaffold(body: DelayedSpinner());
        }
        // 住人データの取得・パースに失敗した場合（例: 2026-09-23の
        // rhingId→rhingSeedリネーム移行漏れで`AppUser.fromJson`が例外を
        // 投げた事例）、既存ユーザーを「ドキュメントが存在しない＝新規
        // ユーザー」と誤判定して下のTermsConsentScreen/RhingSeedSetupScreen
        // （新規登録フロー）へ進めてしまうと、既存データが`.set()`で上書き
        // 消失する重大な事故になる。エラー時は絶対に新規登録フローへ進めず、
        // 再試行可能なエラー画面を表示する（2026-09-24追加、詳細は日記.md
        // 参照）。
        if (snapshot.hasError) {
          return _AuthLoadErrorScreen(
            onRetry: () => setState(() {
              // 代入式を返すと`Future`を返すことになり、`setState`の検査で例外になる
              // （2026-10-17修正、居住地の保存直後に発生）ため、ブロック本体にする。
              _future = _fetchUser();
            }),
          );
        }
        final appUser = snapshot.data!.user;
        if (appUser == null) {
          if (!_termsAgreed) {
            return TermsConsentScreen(
              onAgree: () => setState(() => _termsAgreed = true),
            );
          }
          return RhingSeedSetupScreen(userId: widget.userId);
        }
        if (appUser.accountStatus == AccountStatus.pendingDeletion) {
          return AccountRestoreScreen(
            appUser: appUser,
            onRestored: () => setState(() {
              _future = _fetchUser();
            }),
          );
        }
        if (appUser.accountStatus == AccountStatus.suspended) {
          return AccountSuspendedScreen(
            autoSuspendedUntil: appUser.autoSuspendedUntil,
          );
        }
        // 居住地アンケート未回答（新規登録直後に離脱した人・既存住人・daidai横丁で
        // 先にアカウントだけ作った人の初回ログイン後）は、国を答えるまで先へ
        // 進めない（2026-10-16追加）。管理者は対象外（2026-10-18追加）。
        if (snapshot.data!.residence == null && !snapshot.data!.isAdmin) {
          return ResidenceSurveyScreen(
            userId: appUser.userId,
            onCompleted: () => setState(() {
              _future = _fetchUser();
            }),
          );
        }
        // 新規登録で居住地アンケートの後に離脱した人に、初回の使い方ガイドを
        // 出す（2026-10-17追加）。`guideSeen`がnull＝既存住人には出さない。
        if (appUser.preferences.guideSeen == false && !_guideDone) {
          // 使い方ガイドの前に、見た目を試しながら決める初期設定を出す（2026-10-31追加）。
          if (!_setupDone) {
            return InitialSetupScreen(
              onCompleted: () => setState(() => _setupDone = true),
            );
          }
          return FirstRunTutorialScreen(
            userId: appUser.userId,
            onCompleted: () => setState(() => _guideDone = true),
          );
        }
        return PasscodeLockGate(child: widget.builder(context, appUser));
      },
    );
  }
}

/// 住人データの取得・パースに失敗した際に表示するエラー画面
/// （2026-09-24追加、`_AuthenticatedUserGateState.build`参照）。
class _AuthLoadErrorScreen extends ConsumerWidget {
  const _AuthLoadErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.authLoadErrorTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(strings.authLoadErrorMessage, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: onRetry,
                  child: Text(strings.authLoadErrorRetryButton),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  child: Text(strings.authLoadErrorSignOutButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 未ログイン時のログイン画面。アカウントの追加の途中（[hasPendingAccountAddProvider]）なら、
/// 全画面ではなくポップアップで出す（2026-11-11）。
///
/// 保存された追加の保留があるのに、このセッションで追加を始めていない（＝追加の途中でアプリが
/// 終わった・リロードした、または期限切れ）時は、元のアカウントへ戻す（2026-11-14）。
/// ログイン画面が開いた時に、保留中のアカウントの追加を捨てて元のアカウントへ戻すか
/// （2026-11-24）。保留が無ければ`false`。リダイレクトのログインへ向かう印
/// （`continued`）が有り、チケットの期限内なら、Googleから戻る途中なので`false`
/// （戻した後の続きは、ログイン後に`AuthGate`が引き継ぐ）。
bool shouldRestorePendingAtSignIn(PendingAccountAdd? pending, int nowMs) {
  if (pending == null) return false;
  if (pending.continued && pending.expiresAtMs >= nowMs) return false;
  return true;
}

class _SignInGate extends ConsumerStatefulWidget {
  const _SignInGate();

  @override
  ConsumerState<_SignInGate> createState() => _SignInGateState();
}

class _SignInGateState extends ConsumerState<_SignInGate> {
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreIfLeftOver());
  }

  Future<void> _restoreIfLeftOver() async {
    if (!mounted || ref.read(addStartedThisSessionProvider)) return;
    final switcher = ref.read(accountSwitcherProvider);
    final pending = await switcher.loadPendingAdd();
    if (!mounted ||
        !shouldRestorePendingAtSignIn(
          pending,
          DateTime.now().millisecondsSinceEpoch,
        )) {
      return;
    }
    setState(() => _restoring = true);
    await restoreOriginalAccount(context, ref);
    if (mounted) setState(() => _restoring = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) return const Scaffold(body: DelayedSpinner());
    final adding = ref.watch(hasPendingAccountAddProvider).value ?? false;
    // アカウント追加の途中のポップアップは縦画面だけ。横画面は、普段のログイン画面の
    // デザインのまま出す（追加中の案内とやめる操作は`SavedAccountsSignIn`が出す、2026-11-15）。
    final size = MediaQuery.sizeOf(context);
    return SignInScreen(popup: adding && size.height >= size.width);
  }
}
