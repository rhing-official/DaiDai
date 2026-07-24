import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
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

class _AuthenticatedUserGate extends ConsumerWidget {
  const _AuthenticatedUserGate({required this.userId, required this.builder});

  final String userId;
  final Widget Function(BuildContext context, AppUser currentUser) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userRepository = ref.watch(userRepositoryProvider);

    return FutureBuilder<AppUser?>(
      future: userRepository.getUser(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final appUser = snapshot.data;
        if (appUser == null) {
          return RhingIdSetupScreen(userId: userId);
        }
        return builder(context, appUser);
      },
    );
  }
}
