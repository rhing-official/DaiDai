import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';
import '../../utils/platform_info.dart';
import 'active_call_session.dart';

/// アプリ全体で、自分宛の着信（呼び出し中の通話）を監視する。
/// モバイル実機では検知したら自動でCallScreenを開く。PC/Webでは
/// フルスクリーン画面を経由せず`activeCallSessionProvider`を直接開始し、
/// `EmbeddedCallPane`（該当の会話を見ている間）・`PinnedCallOverlay`
/// （見ていない間、右上ミニ表示）に着信中の表示・応答/拒否操作を委ねる
/// （2026-09-12変更、発信側のPC分岐＝`talks_tab.dart`の`_startCall`と対称に
/// した。以前はPCでも着信は必ずフルスクリーンだった）。
/// HomeScreenの上位でラップして使う。
class IncomingCallListener extends ConsumerStatefulWidget {
  const IncomingCallListener({
    required this.currentUserId,
    required this.child,
    super.key,
  });

  final String currentUserId;
  final Widget child;

  @override
  ConsumerState<IncomingCallListener> createState() =>
      _IncomingCallListenerState();
}

class _IncomingCallListenerState extends ConsumerState<IncomingCallListener> {
  String? _openCallId;

  @override
  Widget build(BuildContext context) {
    ref.listen(_incomingCallProvider(widget.currentUserId), (previous, next) {
      final call = next.asData?.value;
      if (call == null) return;
      if (!isMobileCallPlatform) {
        // PC/Web: フルスクリーンを経由せず直接セッションを開始する。
        // startOneToOne自体が同じ通話への重複アタッチを防ぐため
        // （active_call_session.dart参照）、_openCallIdでの重複防止は不要。
        ref
            .read(activeCallSessionProvider.notifier)
            .startOneToOne(
              call: call,
              isCaller: false,
              callRepository: ref.read(callRepositoryProvider),
              directMessageRepository: ref.read(
                directMessageRepositoryProvider,
              ),
            );
        return;
      }
      if (call.callId == _openCallId) return;
      _openCallId = call.callId;
      ref
          .read(goRouterProvider)
          .push(
            '/call',
            extra: CallArgs(
              call: call,
              isCaller: false,
              currentUserId: widget.currentUserId,
            ),
          )
          .then((_) {
            _openCallId = null;
          });
    });

    return widget.child;
  }
}

final _incomingCallProvider = StreamProvider.family((ref, String userId) {
  return ref.watch(callRepositoryProvider).watchIncomingCall(userId);
});
