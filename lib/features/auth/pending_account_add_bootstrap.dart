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
    ref.invalidate(savedAccountsProvider);
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
