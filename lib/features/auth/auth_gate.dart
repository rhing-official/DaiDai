import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_preferences_sync.dart';
import 'account_restore_screen.dart';
import 'rhing_id_setup_screen.dart';
import 'sign_in_screen.dart';

/// 認証状態・Rhing ID登録状態に応じて表示を切り替える汎用ゲート。
/// ログイン済み・Rhing ID登録済みになった時点で[builder]を呼ぶ。
/// [AppGate]（アプリのルート画面）と、招待リンク（`/invite/:rhingId`）など
/// 未ログインでも開かれうる入り口の両方から使う。
class AuthGate extends ConsumerWidget {
  const AuthGate({required this.builder, super.key});

  final Widget Function(BuildContext context, AppUser currentUser) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
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
      if (user != null) applyRemoteUserPreferences(ref, user.preferences);
      return user;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final appUser = snapshot.data;
        if (appUser == null) {
          return RhingIdSetupScreen(userId: widget.userId);
        }
        if (appUser.accountStatus == AccountStatus.pendingDeletion) {
          return AccountRestoreScreen(
            appUser: appUser,
            onRestored: () => setState(() => _future = _fetchUser()),
          );
        }
        return widget.builder(context, appUser);
      },
    );
  }
}
