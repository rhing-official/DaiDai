import '../../utils/auto_dismiss_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/account_switcher_providers.dart';
import '../../l10n/strings.dart';
import '../../models/saved_account.dart';
import 'restore_original_account.dart';
import '../../repositories/switch_session_repository.dart';
import '../../widgets/account_avatar.dart';
import '../settings/account_switcher_section.dart';

/// ログイン画面の「保存したアカウントで続ける」（2026-11-11、複数アカウント、当面はWebだけ）。
/// 切り替え用に保存したアカウントがあれば、ログインし直さずに続けられる。アカウントの追加の
/// 途中なら、その案内（と、やめる操作）も出す。
class SavedAccountsSignIn extends ConsumerStatefulWidget {
  const SavedAccountsSignIn({super.key});

  @override
  ConsumerState<SavedAccountsSignIn> createState() =>
      _SavedAccountsSignInState();
}

class _SavedAccountsSignInState extends ConsumerState<SavedAccountsSignIn> {
  /// 切り替え中のアカウント（くるくるで読み込み中を伝える、2026-11-14）。成功すると
  /// 再読み込みされるので、成功時はそのまま回し続ける。
  String? _switchingUid;

  Future<void> _switch(SavedAccount account, Strings strings) async {
    if (_switchingUid != null) return;
    setState(() => _switchingUid = account.uid);
    try {
      await ref.read(accountSwitcherProvider).switchTo(account);
    } on SwitchAccountException catch (error) {
      if (mounted) setState(() => _switchingUid = null);
      if (mounted) {
        showAutoDismissBanner(
          context,
          message: switchAccountFailureMessage(
            strings,
            error,
            fallback: strings.switchAccountsFailed,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _switchingUid = null);
      if (mounted) {
        showAutoDismissBanner(context, message: strings.switchAccountsFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: () => restoreOriginalAccount(context, ref),
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
              trailing: _switchingUid == account.uid
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : null,
              enabled: _switchingUid == null || _switchingUid == account.uid,
              onTap: _switchingUid == null
                  ? () => _switch(account, strings)
                  : null,
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
