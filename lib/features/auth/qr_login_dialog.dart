import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/app_dialog.dart';
import '../../l10n/strings.dart';
import '../../utils/platform_info.dart';
import 'qr_login_panel.dart';

/// QRコードログイン（未ログイン端末側、2026-08-09追加。2026-11-14に設定側の
/// `IssueQrLoginDialog`と対称な構成に）。開くとすぐに`qrLoginSessions`にpendingな
/// セッションを作ってQRコードを表示し、ログイン済みの別端末（設定＞アカウント＞QRコードで
/// ログイン＞「QRコードを読み取る」）が承認するのを待つ。承認を検知したら自動的に
/// カスタムトークンでサインインして閉じる（以降は`AuthGate`が認証状態の変化で遷移する）。
/// 下の「QRコードを読み取る」（カメラのある端末のみ）は逆向き: ログイン済みの端末が出した
/// QRをこの端末で読み取ってログインする。押すと[scanRequested]で閉じ、呼び出し側が
/// 読み取りを始める。
class QrLoginDialog extends ConsumerWidget {
  const QrLoginDialog({super.key});

  static const scanRequested = 'scan';

  /// 閉じた時の結果。読み取りが要求されて閉じたなら`true`。
  static Future<bool> show(BuildContext context) async {
    final result = await showAppDialog<String>(
      context: context,
      builder: (_) => const QrLoginDialog(),
    );
    return result == scanRequested;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrLoginPanel(onClaimed: () => Navigator.of(context).pop()),
            if (isQrScanCapablePlatform) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(scanRequested),
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(strings.qrLoginScanButton),
              ),
            ],
          ],
        ),
      ),
    );
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(strings.cancel),
      ),
    ];

    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : KeyboardAlertDialog(title: title, content: content, actions: actions);
  }
}
