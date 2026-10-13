import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../router/back_stack.dart';

/// 起動時のURLに`?backdebug=1`が付いていたか（戻る操作の診断用、2026-10-13）。
/// 通常のURLでは何も出ない。
final bool kBackDebugEnabled = Uri.base.queryParameters['backdebug'] == '1';

/// 戻る操作の直近のログ（どのルート・層・ダイアログが何で閉じたか）を画面左下に出す。
class BackDebugOverlay extends ConsumerWidget {
  const BackDebugOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kBackDebugEnabled) return const SizedBox.shrink();
    final controller = ref.watch(backStackControllerProvider);
    return Positioned(
      left: 0,
      bottom: 0,
      right: 0,
      child: IgnorePointer(
        child: ValueListenableBuilder<List<String>>(
          valueListenable: controller.debugLines,
          builder: (context, lines, _) => Container(
            color: Colors.black87,
            padding: const EdgeInsets.all(4),
            child: Text(
              lines.reversed.take(10).join('\n'),
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 10,
                fontFamily: 'monospace',
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
