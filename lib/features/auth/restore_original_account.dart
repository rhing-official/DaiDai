import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers/account_switcher_providers.dart';
import '../../repositories/switch_session_repository.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../settings/account_toggle.dart' show switchAccountFailureMessage;

/// アカウントの追加を終えずにやめた時、追加を始めた元のアカウントへ戻す（2026-11-14）。
/// 成功すると再読み込みされる。戻せなかった時（保存が無い・失効・極み切れ・通信不可）は
/// バナーで知らせ、通常のログイン画面になる。
Future<void> restoreOriginalAccount(BuildContext context, WidgetRef ref) async {
  final strings = ref.read(appStringsProvider);
  try {
    await ref.read(accountSwitcherProvider).restoreOriginal();
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
  } catch (_) {
    if (context.mounted) {
      showAutoDismissBanner(context, message: strings.switchAccountsFailed);
    }
  }
  ref.invalidate(hasPendingAccountAddProvider);
}
