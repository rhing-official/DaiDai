import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/glass/glass_dialog.dart';

/// パスキーで新しくアカウントを作る前に出す確認（2026-11-18）。
///
/// パスキーを失った時の復旧手段（秘密の質問）を廃止し、バックアップコードも採用しない
/// ため、パスキーだけのアカウントは、パスキーを失うと入れなくなる（事前に別のパスキーを
/// 登録するか、後からGoogle・Appleを連携しておく場合を除く）。その事実を、アカウントを
/// 作る前に伝え、「理解した」にチェックを入れた時だけ続けられる。
/// 続ける時は`true`、キャンセルは`false`（又は閉じて`null`）を返す。
class PasskeyCreateWarningDialog extends ConsumerStatefulWidget {
  const PasskeyCreateWarningDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showAppDialog<bool>(
      context: context,
      builder: (_) => const PasskeyCreateWarningDialog(),
    );
    return result == true;
  }

  @override
  ConsumerState<PasskeyCreateWarningDialog> createState() =>
      _PasskeyCreateWarningDialogState();
}

class _PasskeyCreateWarningDialogState
    extends ConsumerState<PasskeyCreateWarningDialog> {
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final title = Text(strings.passkeyCreateWarningTitle);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.passkeyCreateWarningBody),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _understood,
          onChanged: (v) => setState(() => _understood = v ?? false),
          title: Text(strings.passkeyCreateWarningCheckbox),
        ),
      ],
    );
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(strings.cancel),
      ),
      FilledButton(
        onPressed: _understood ? () => Navigator.of(context).pop(true) : null,
        child: Text(strings.passkeyCreateWarningContinue),
      ),
    ];
    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : KeyboardAlertDialog(title: title, content: content, actions: actions);
  }
}
