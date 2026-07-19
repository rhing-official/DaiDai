import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../providers/repository_providers.dart';
import 'auth/rhing_id_setup_screen.dart';
import 'auth/sign_in_screen.dart';
import 'home/home_screen.dart';

/// 認証状態・Rhing ID登録状態に応じて表示する画面を切り替える。
class AppGate extends ConsumerWidget {
  const AppGate({super.key});

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
        return _UserGate(userId: user.uid);
      },
    );
  }
}

class _UserGate extends ConsumerWidget {
  const _UserGate({required this.userId});

  final String userId;

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
        return HomeScreen(currentUser: appUser);
      },
    );
  }
}
