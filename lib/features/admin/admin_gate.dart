import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
import '../not_found/not_found_screen.dart';
import 'admin_panel_screen.dart';

/// `/admin`（隠しルート）の入り口。管理者クレーム（[isAdminProvider]）を
/// 確認し、管理者なら[AdminPanelScreen]を、管理者でなければ未定義URLと同じ
/// 「404 美術館」（[NotFoundScreen]）を表示する（2026-08-12新設、2026-10-10に
/// 非管理者向けを変更）。以前は非管理者に「権限がありません」と初回管理者
/// 登録ボタンを出していたが、管理画面の存在・URLを推測されないよう、通常の
/// 存在しないURLと区別が付かない表示にした（認可の本体はFirebaseの
/// カスタムクレームとCloud Functions側の確認で、この画面は変更していない）。
/// 初回管理者の登録（`grantFirstAdminOnce`）の導線はここから外した。通常の
/// ナビゲーションからは導線を出さず、URLを直接開いた場合のみ到達する想定。
/// 管理画面の見た目は利用者画面と同じテーマ（ユーザー設定のUIスタイル・
/// アクセントカラー・フォント）に従う（2026-10-10、以前はモノクロ固定の
/// `AppTheme.admin`でラップしていた）。
class AdminGate extends ConsumerWidget {
  const AdminGate({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdminAsync = ref.watch(isAdminProvider);
    return isAdminAsync.when(
      loading: () => const Scaffold(body: SizedBox.shrink()),
      // 判定に失敗した場合も、理由を表示せず存在しないページ扱いにする。
      error: (_, _) => const NotFoundScreen(),
      data: (isAdmin) => isAdmin
          ? AdminPanelScreen(currentUser: currentUser)
          : const NotFoundScreen(),
    );
  }
}
