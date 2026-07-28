import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';

/// アカウント削除申請中（[AccountStatus.pendingDeletion]）のユーザーに
/// 表示する復元プロンプト。30日間はここから復元できる。何もしなければ
/// 31日目にCloud Functionsの定期処理がサーバーから全情報を完全削除する
/// （`UserRepository.requestAccountDeletion`/`restoreAccount`参照）。
class AccountRestoreScreen extends ConsumerStatefulWidget {
  const AccountRestoreScreen({
    required this.appUser,
    required this.onRestored,
    super.key,
  });

  final AppUser appUser;
  final VoidCallback onRestored;

  @override
  ConsumerState<AccountRestoreScreen> createState() =>
      _AccountRestoreScreenState();
}

class _AccountRestoreScreenState extends ConsumerState<AccountRestoreScreen> {
  bool _isSubmitting = false;

  int get _remainingDays {
    final requestedAt = widget.appUser.deletionRequestedAt?.toDate();
    if (requestedAt == null) return 0;
    final elapsed = DateTime.now().difference(requestedAt).inDays;
    final remaining = 31 - elapsed;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> _restore() async {
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(userRepositoryProvider)
          .restoreAccount(widget.appUser.userId);
      widget.onRestored();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.accountRestoreTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  strings.accountRestoreMessage(_remainingDays),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSubmitting ? null : _restore,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(strings.accountRestoreButton),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => ref.read(authRepositoryProvider).signOut(),
                  child: Text(strings.accountRestoreSignOutButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
