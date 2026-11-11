import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/account_switcher_providers.dart';
import '../../l10n/strings.dart';
import '../../repositories/switch_session_repository.dart';
import '../settings/account_switcher_section.dart';

/// アカウントの追加の途中でログインした直後に、そのアカウントを切り替え用に保存する
/// （2026-11-11、複数アカウント、当面はWebだけ）。`AppGate`でホームを包む。
/// 保留中の追加が無ければ何もしない。
class PendingAccountAddBootstrap extends ConsumerStatefulWidget {
  const PendingAccountAddBootstrap({
    required this.currentUser,
    required this.child,
    super.key,
  });

  final AppUser currentUser;
  final Widget child;

  @override
  ConsumerState<PendingAccountAddBootstrap> createState() =>
      _PendingAccountAddBootstrapState();
}

class _PendingAccountAddBootstrapState
    extends ConsumerState<PendingAccountAddBootstrap> {
  @override
  void initState() {
    super.initState();
    if (kIsWeb) _complete();
  }

  @override
  void didUpdateWidget(PendingAccountAddBootstrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.currentUser;
    final now = widget.currentUser;
    if (kIsWeb &&
        (old.effectiveIcon?.url != now.effectiveIcon?.url ||
            old.effectiveIconFocalFor(null)?.dx !=
                now.effectiveIconFocalFor(null)?.dx ||
            old.effectiveIconFocalFor(null)?.dy !=
                now.effectiveIconFocalFor(null)?.dy ||
            old.effectiveIconFocalFor(null)?.scale !=
                now.effectiveIconFocalFor(null)?.scale)) {
      _refreshIcon();
    }
  }

  Future<void> _refreshIcon() async {
    try {
      if (await ref
          .read(accountSwitcherProvider)
          .refreshProfile(widget.currentUser)) {
        ref.invalidate(savedAccountsProvider);
      }
    } on Object {
      // 表示用の写しなので、失敗しても何もしない。
    }
  }

  Future<void> _complete() async {
    final strings = ref.read(appStringsProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    String? message;
    try {
      final added = await ref
          .read(accountSwitcherProvider)
          .completePendingAdd(widget.currentUser);
      if (added) message = strings.switchAccountsAdded;
    } on SwitchAccountException catch (error) {
      message = switchAccountFailureMessage(
        strings,
        error,
        fallback: strings.switchAccountsAddFailed,
      );
    } on Object {
      message = strings.switchAccountsAddFailed;
    }
    await _refreshIcon();
    ref.invalidate(savedAccountsProvider);
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
