import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers/repository_providers.dart';

/// アカウント停止中（[AccountStatus.suspended]）のユーザーに表示する画面。
/// [autoSuspendedUntil]が無い場合は運営の手動停止（[AccountRestoreScreen]と
/// 違い自己解除の手段は無くサインアウトのみ）。ある場合は技術仕様書8.4の
/// 期限付き自動停止（スパム違反の累計による段階的停止）で、解除までの
/// 目安時間を表示する（2026-09-07追加、`AuthGate`参照）。
class AccountSuspendedScreen extends ConsumerWidget {
  const AccountSuspendedScreen({this.autoSuspendedUntil, super.key});

  final Timestamp? autoSuspendedUntil;

  /// 「約12時間」「約7日」のような目安表示に丸める。
  String _formatRemaining(Duration remaining) {
    if (remaining.inDays >= 1) return '約${remaining.inDays}日';
    return '約${remaining.inHours.clamp(1, 23)}時間';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final remaining = autoSuspendedUntil?.toDate().difference(DateTime.now());
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.accountSuspendedTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  strings.accountSuspendedMessage,
                  textAlign: TextAlign.center,
                ),
                if (remaining != null && !remaining.isNegative) ...[
                  const SizedBox(height: 8),
                  Text(
                    strings.accountSuspendedAutoUntilTemplate(
                      _formatRemaining(remaining),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  child: Text(strings.accountSuspendedSignOutButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
