import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../l10n/strings.dart';
import 'dialog_keyboard_shortcuts.dart';
import 'glass/glass_dialog.dart';

/// ダウンロードボタンを押した時の確認ダイアログ（2026-10-16追加）。
/// メッセージの添付ファイルとノートのダウンロードで共通に使う。
/// 「ダウンロード」が押されたら`true`、キャンセル・閉じたら`false`を返す。
Future<bool> confirmDownload(
  BuildContext context,
  WidgetRef ref, {
  required String fileName,
}) async {
  final strings = ref.read(appStringsProvider);
  final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final title = Text(strings.downloadConfirmTitle);
      final content = Text(strings.downloadConfirmMessage(fileName));
      final actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.downloadConfirmButton),
        ),
      ];
      // 横幅いっぱいに広がらないよう幅を制限する（他の確認ダイアログと同じ）。
      return isGlass
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: GlassAlertDialog(
                title: title,
                content: content,
                actions: actions,
              ),
            )
          : KeyboardAlertDialog(
              constraints: const BoxConstraints(maxWidth: 400),
              title: title,
              content: content,
              actions: actions,
            );
    },
  );
  return confirmed == true;
}
