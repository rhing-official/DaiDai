import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';

/// アプリ全体で、自分宛の着信（呼び出し中の通話）を監視し、
/// 検知したら自動でCallScreenを開く。HomeScreenの上位でラップして使う。
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
      if (call == null || call.callId == _openCallId) return;
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
