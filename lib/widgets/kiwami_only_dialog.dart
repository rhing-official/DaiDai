import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../providers/repository_providers.dart';
import '../utils/kiwami.dart';

/// 極み限定の機能を、極みでない人が使おうとした時の案内ダイアログ（2026-10-17追加）。
/// 「極みを購入する」から、購入者のuid付きでStripeの決済リンクを開く。
Future<void> showKiwamiOnlyDialog(
  BuildContext context,
  Strings strings, {
  required String body,
}) {
  final userId = ProviderScope.containerOf(
    context,
  ).read(authStateProvider).value?.uid;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.kiwamiOnlyTitle),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(strings.kiwamiOnlyClose),
        ),
        if (userId != null)
          FilledButton(
            onPressed: () {
              launchUrl(
                kiwamiPurchaseUri(userId),
                mode: LaunchMode.externalApplication,
              );
              Navigator.of(dialogContext).pop();
            },
            child: Text(strings.kiwamiPurchase),
          ),
      ],
    ),
  );
}
