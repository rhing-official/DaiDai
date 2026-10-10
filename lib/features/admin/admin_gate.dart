import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
import '../../theme/app_theme.dart';
import 'admin_panel_screen.dart';

/// `/admin`（隠しルート）の入り口。管理者クレーム（[isAdminProvider]）を
/// 確認し、管理者なら[AdminPanelScreen]を、管理者でなければ「存在しない
/// ページ」と同じ見た目の画面を表示する（2026-08-12新設、2026-10-10に
/// 非管理者向けを変更）。以前は非管理者に「権限がありません」と初回管理者
/// 登録ボタンを出していたが、管理画面の存在・URLを推測されないよう、通常の
/// 存在しないURLと区別が付かない表示にした（認可の本体はFirebaseの
/// カスタムクレームとCloud Functions側の確認で、この画面は変更していない）。
/// 初回管理者の登録（`grantFirstAdminOnce`）の導線はここから外した。通常の
/// ナビゲーションからは導線を出さず、URLを直接開いた場合のみ到達する想定。
class AdminGate extends ConsumerWidget {
  const AdminGate({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Theme(
      data: AppTheme.admin(Theme.of(context).brightness),
      child: Builder(
        builder: (context) {
          // ユーザー設定のアクセントカラーに依存させないため、管理画面全体を
          // モノクロテーマ（[AppTheme.admin]）でラップする（2026-08-26追加）。
          final isAdminAsync = ref.watch(isAdminProvider);
          return isAdminAsync.when(
            loading: () => const Scaffold(body: SizedBox.shrink()),
            // 判定に失敗した場合も、理由を表示せず存在しないページ扱いにする。
            error: (_, _) => const _NotFoundView(),
            data: (isAdmin) => isAdmin
                ? AdminPanelScreen(currentUser: currentUser)
                : const _NotFoundView(),
          );
        },
      ),
    );
  }
}

/// 存在しないURLを開いた時の表示（管理者でない人が`/admin`を開いた時に使う）。
class _NotFoundView extends StatelessWidget {
  const _NotFoundView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('ページが見つかりません'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.go('/'),
                child: const Text('ホームへ戻る'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
