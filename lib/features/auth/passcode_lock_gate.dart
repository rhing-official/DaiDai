import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/passcode_lock_provider.dart';
import '../../providers/repository_providers.dart';
import 'passcode_lock_screen.dart';

/// サインイン済み・アカウント状態も正常だが、端末側のパスコードロックが
/// 有効な場合に[child]の代わりに[PasscodeLockScreen]を表示するゲート
/// （2026-09-11追加）。`AuthGate`（`_AuthenticatedUserGateState.build()`）の
/// 最後、`widget.builder`呼び出しをラップする形で挟み込む。招待リンク等の
/// 入り口を含め`AuthGate`を経由する全ての画面に一貫してロックがかかる。
class PasscodeLockGate extends ConsumerStatefulWidget {
  const PasscodeLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PasscodeLockGate> createState() => _PasscodeLockGateState();
}

class _PasscodeLockGateState extends ConsumerState<PasscodeLockGate> {
  // `build()`のたびに新しいFutureを生成すると、そのたびにFutureBuilderが
  // ConnectionState.waitingへ戻ってしまう（`_DmChatPaneState
  // ._messagesController`のdocコメントと同じ理由）ため、`initState`で
  // 一度だけ生成する。
  late final Future<bool> _isPasscodeSetFuture = ref
      .read(passcodeRepositoryProvider)
      .isPasscodeSet();

  @override
  Widget build(BuildContext context) {
    final unlocked = ref.watch(isAppUnlockedProvider);
    if (unlocked) return widget.child;

    return FutureBuilder<bool>(
      future: _isPasscodeSetFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == true) return const PasscodeLockScreen();
        return widget.child;
      },
    );
  }
}
