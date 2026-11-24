import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/strings.dart';

/// 緊急の発信（通話ボタンの長押し、2026-11-25）の確認。受け手の端末のおやすみモードを貫通して
/// 鳴るため、乱用しないよう、初めて使う時だけ確認する。確認したら端末に覚え、以後は聞かない。
/// 発信してよければ`true`。
const kUrgentCallConfirmedKey = 'urgentCallConfirmed';

Future<bool> confirmUrgentCall(BuildContext context, Strings strings) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(kUrgentCallConfirmedKey) ?? false) return true;
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
  if (ok != true) return false;
  await prefs.setBool(kUrgentCallConfirmedKey, true);
  return true;
}
