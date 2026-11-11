import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/saved_account.dart';
import '../../providers/account_switcher_providers.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../repositories/switch_session_repository.dart';
import '../../services/account_switcher.dart';
import '../../utils/kiwami.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/generated_avatar.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/gekiga/gekiga_section_header.dart';
import '../../widgets/gekiga/settings_tile.dart';
import '../../widgets/kiwami_only_dialog.dart';

/// 画面に出す、切り替えの失敗の説明（表示言語に合わせる。サーバーの文言は使わない）。
String switchAccountFailureMessage(
  Strings strings,
  SwitchAccountException error, {
  required String fallback,
}) => switch (error.kind) {
  SwitchAccountFailure.kiwamiRequired => strings.switchAccountsKiwamiLapsed,
  SwitchAccountFailure.reloginNeeded => strings.switchAccountsReloginNeeded,
  SwitchAccountFailure.limitReached => strings.switchAccountsLimit,
  SwitchAccountFailure.other => fallback,
};

/// 設定>アカウントの「アカウントの切り替え」（2026-11-11、極みの特典、当面はWebだけ）。
/// この端末に保存したアカウントの一覧・ワンタップの切り替え・追加・取り外し。
/// 設計は`文書/複数アカウント.md`。
class AccountSwitcherSection extends ConsumerWidget {
  const AccountSwitcherSection({
    required this.strings,
    required this.currentUser,
    super.key,
  });

  final Strings strings;
  final AppUser currentUser;

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final switcher = ref.read(accountSwitcherProvider);
    if (!isKiwami(currentUser)) {
      await showKiwamiOnlyDialog(
        context,
        strings,
        body: strings.switchAccountsKiwamiBody,
      );
      return;
    }
    if (!await switcher.canAdd(currentUser)) {
      if (context.mounted) _snack(context, strings.switchAccountsLimit);
      return;
    }
    if (!context.mounted) return;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.switchAccountsTrustTitle),
        content: Text(strings.switchAccountsTrustBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.switchAccountsTrustConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await switcher.startAdd(currentUser);
    } on SwitchAccountException catch (error) {
      if (context.mounted) {
        _snack(
          context,
          switchAccountFailureMessage(
            strings,
            error,
            fallback: strings.switchAccountsAddFailed,
          ),
        );
      }
    }
  }

  Future<void> _switch(
    BuildContext context,
    WidgetRef ref,
    SavedAccount account,
  ) async {
    try {
      await ref.read(accountSwitcherProvider).switchTo(account);
    } on SwitchAccountException catch (error) {
      if (context.mounted) {
        _snack(
          context,
          switchAccountFailureMessage(
            strings,
            error,
            fallback: strings.switchAccountsFailed,
          ),
        );
      }
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    SavedAccount account,
  ) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.switchAccountsRemoveTitle),
        content: Text(strings.switchAccountsRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.switchAccountsRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(accountSwitcherProvider).forget(account.uid);
    ref.invalidate(savedAccountsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 当面はWebだけ（他のプラットフォームは、再読み込みの代わりが未実装）。
    if (!kIsWeb) return const SizedBox.shrink();
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final saved = ref.watch(savedAccountsProvider).value ?? const [];
    final others = [
      for (final a in saved)
        if (a.uid != currentUser.userId) a,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: GekigaSectionHeader(strings.switchAccountsSection),
        ),
        SettingsTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: GeneratedAvatar(
            seed: currentUser.userId,
            label: currentUser.rhingSeed,
            size: 36,
          ),
          title: Text('@${currentUser.rhingSeed}'),
          subtitle: Text(strings.switchAccountsCurrent),
          selected: true,
        ),
        for (final account in others)
          SettingsTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: GeneratedAvatar(
              seed: account.uid,
              label: account.rhingSeed,
              size: 36,
            ),
            title: Text('@${account.rhingSeed}'),
            trailing: isGekiga
                ? Tooltip(
                    message: strings.switchAccountsRemove,
                    child: GekigaIconButton(
                      icon: Icons.close,
                      onPressed: () => _remove(context, ref, account),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: strings.switchAccountsRemove,
                    onPressed: () => _remove(context, ref, account),
                  ),
            onTap: () => _switch(context, ref, account),
          ),
        if (others.length + 1 < AccountSwitcher.maxAccounts)
          SettingsTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: Text(strings.switchAccountsAdd),
            subtitle: Text(strings.switchAccountsAddHint),
            onTap: () => _add(context, ref),
          ),
      ],
    );
  }
}
