import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// 緊急の発信（通話ボタンの長押し、2026-11-25）の確認。受け手の端末のおやすみモードを貫通して
/// 鳴るため、乱用しないよう、毎回確認する。
/// 発信してよければ`true`。
Future<bool> confirmUrgentCall(BuildContext context, Strings strings) async {
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.urgentCallConfirmTitle),
      content: Text(strings.urgentCallConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(strings.urgentCallConfirmAction),
        ),
      ],
    ),
  );
  return ok == true;
}
