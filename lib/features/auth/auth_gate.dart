import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_preferences_sync.dart';
import 'account_restore_screen.dart';
import 'account_suspended_screen.dart';
import 'passcode_lock_gate.dart';
import 'rhing_seed_setup_screen.dart';
import 'sign_in_screen.dart';
import 'terms_consent_screen.dart';

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
      loading: () => const Scaffold(body: SizedBox.shrink()),
      error: (error, _) => Scaffold(body: Center(child: Text('エラー: $error'))),
      data: (user) {
        if (user == null) {
          return const SignInScreen();
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
  late Future<AppUser?> _future;

  /// 新規アカウント作成時、[RhingSeedSetupScreen]の前に[TermsConsentScreen]で
  /// 同意したかどうか（このセッション内のみの一時的な状態、2026-09-14追加）。
  bool _termsAgreed = false;

  @override
  void initState() {
    super.initState();
    _future = _fetchUser();
  }

  // 端末をまたいで同期する表示設定（アクセントカラー・外観・表示言語等）を、
  // ログイン直後に一度だけFirestoreの値で上書きする（[applyRemoteUserPreferences]）。
  // アカウント復元後にユーザーを再取得する際も同じ処理でよいため、
  // [AccountRestoreScreen.onRestored]からも呼び直す。
  Future<AppUser?> _fetchUser() {
    return ref.read(userRepositoryProvider).getUser(widget.userId).then((user) {
      if (user != null) {
        applyRemoteUserPreferences(ref, user.preferences);
        // 最終ログイン日時（管理画面向け）。自動ログインでの再開時も含めて
        // 認証済みセッションを確認するたびに更新する。結果を待つ必要は
        // 無いためawaitしない。
        ref.read(userRepositoryProvider).touchLastLogin(user.userId);
      }
      return user;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: SizedBox.shrink());
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
            onRetry: () => setState(() => _future = _fetchUser()),
          );
        }
        final appUser = snapshot.data;
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
            onRestored: () => setState(() => _future = _fetchUser()),
          );
        }
        if (appUser.accountStatus == AccountStatus.suspended) {
          return AccountSuspendedScreen(
            autoSuspendedUntil: appUser.autoSuspendedUntil,
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
