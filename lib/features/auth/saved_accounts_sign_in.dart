import '../../utils/auto_dismiss_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/account_switcher_providers.dart';
import '../../l10n/strings.dart';
import '../../repositories/switch_session_repository.dart';
import '../../widgets/account_avatar.dart';
import '../settings/account_switcher_section.dart';

/// ログイン画面の「保存したアカウントで続ける」（2026-11-11、複数アカウント、当面はWebだけ）。
/// 切り替え用に保存したアカウントがあれば、ログインし直さずに続けられる。アカウントの追加の
/// 途中なら、その案内（と、やめる操作）も出す。
class SavedAccountsSignIn extends ConsumerWidget {
  const SavedAccountsSignIn({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final saved = ref.watch(savedAccountsProvider).value ?? const [];
    final pending = ref.watch(hasPendingAccountAddProvider).value ?? false;
    if (saved.isEmpty && !pending) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending) ...[
          Text(strings.switchAccountsAddingBanner, textAlign: TextAlign.center),
          TextButton(
            onPressed: () async {
              await ref.read(accountSwitcherProvider).cancelPendingAdd();
              ref.invalidate(hasPendingAccountAddProvider);
            },
            child: Text(strings.switchAccountsCancelAdd),
          ),
        ],
        if (saved.isNotEmpty) ...[
          Text(
            strings.switchAccountsSavedTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final account in saved)
            ListTile(
              leading: AccountAvatar(
                uid: account.uid,
                rhingSeed: account.rhingSeed,
                iconUrl: account.iconUrl,
                iconFocal: account.iconFocal,
              ),
              title: Text('@${account.rhingSeed}'),
              onTap: () async {
                try {
                  await ref.read(accountSwitcherProvider).switchTo(account);
                } on SwitchAccountException catch (error) {
                  if (context.mounted) {
                    showAutoDismissBanner(
                      context,
                      message: switchAccountFailureMessage(
                        strings,
                        error,
                        fallback: strings.switchAccountsFailed,
                      ),
                    );
                  }
                }
              },
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
