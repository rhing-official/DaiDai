import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../l10n/strings.dart';
import '../utils/notification_target.dart';
import 'home_skeleton.dart';

/// 別アカウント宛ての着信・通知から宛先のアカウントへ切り替えている間、全画面で出す
/// スケルトン（2026-11-25）。切り替えは時間が掛かり、進んでいるか分からなかった為。
/// 全ルートの最前面（`main.dart`の`builder`）に置く。進行中でなければ何も出さない。
class AccountSwitchOverlay extends ConsumerWidget {
  const AccountSwitchOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<bool>(
      valueListenable: accountSwitchBusy,
      builder: (context, busy, _) {
        if (!busy) return const SizedBox.shrink();
        final label = ref.watch(appStringsProvider).switchAccountsSwitching;
        return Positioned.fill(
          child: PointerInterceptor(
            child: Material(
              child: Stack(
                children: [
                  const Positioned.fill(child: HomeSkeleton()),
                  Align(
                    alignment: const Alignment(0, 0.85),
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
