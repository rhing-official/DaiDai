import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/app_dialog.dart';
import '../../l10n/strings.dart';
import 'qr_login_panel.dart';

/// QRコードログイン（未ログイン端末側、2026-08-09追加）。開くとすぐに
/// `qrLoginSessions`にpendingなセッションを作成してQRコードを表示し、
/// ログイン済みの別端末（設定＞アカウント＞セキュリティ＞QRコードによる
/// ログインからスキャン）が承認するのを待つ。承認を検知したら自動的に
/// カスタムトークンでサインインし、ダイアログを閉じる（以降は`AuthGate`が
/// 認証状態の変化を検知して自動的に画面遷移する）。
class QrLoginDialog extends ConsumerWidget {
  const QrLoginDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showAppDialog<bool>(
      context: context,
      builder: (_) => const QrLoginDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;

    final title = Text(strings.qrLoginDialogTitle);
    // QRコードの表示と承認待ちは`QrLoginPanel`が担う。
    final content = SizedBox(
      width: 280,
      child: SingleChildScrollView(
        child: QrLoginPanel(onClaimed: () => Navigator.of(context).pop(true)),
      ),
    );
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(strings.cancel),
      ),
    ];

    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : KeyboardAlertDialog(title: title, content: content, actions: actions);
  }
}
