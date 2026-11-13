import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/block_providers.dart';
import '../../providers/repository_providers.dart';
import '../../models/call.dart';
import 'active_call_session.dart';
import 'call_ring_timeout.dart';

/// アプリ全体で、自分宛の着信（呼び出し中の通話）を監視する。
/// モバイル実機では検知したら自動でCallScreenを開く。PC/Webでは
/// フルスクリーン画面を経由せず`activeCallSessionProvider`を直接開始し、
/// `PinnedCallOverlay`（右上ミニ表示）に着信中の表示・応答/拒否操作を委ね、
/// 応答すると`CallOverlay`が今の画面の上に通話画面を重ねる（2026-10-23）
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
  @override
  Widget build(BuildContext context) {
    ref.listen(_incomingCallProvider(widget.currentUserId), (previous, next) {
      final call = next.asData?.value;
      if (call == null) return;
      // ブロック中の相手からの着信は無視する（2026-10-11）。拒否は書き込先ず、
      // 発信側にはブロックが分からないまま呼び出し中として終わる。
      final blocked =
          ref.read(blockedUserIdsProvider(widget.currentUserId)).value ??
          const <String>{};
      if (blocked.contains(call.callerId)) return;
      // 終了が書かれずに`ringing`のまま残った古い通話は鳴らさず、不在着信として片付ける
      // （2026-11-03、URLを開くと終わった通話の着信音が鳴る不具合）。
      if (!isCallRingFresh(createdAt: call.createdAt, now: DateTime.now())) {
        ref
            .read(callRepositoryProvider)
            .updateStatus(call.callId, CallStatus.missed)
            .catchError((_) {});
        return;
      }
      // 別の会話で通話中なら、その通話を切らずに着信は受けない（発信側は呼び出しの
      // タイムアウトで不在着信になる）。同じ相手の古い通話は終了して受ける（2026-11-13）。
      if (!ref
          .read(activeCallSessionProvider.notifier)
          .canAcceptIncomingOneToOne(call)) {
        return;
      }
      // フルスクリーンを経由せず直接セッションを開始する（PC・Web・アプリ共通）。
      // 応答・拒否は`IncomingCallBannerOverlay`のバナーだけで行う（2026-11-03、
      // アプリも統一）。startOneToOne自体が同じ通話への重複アタッチを防ぐ
      // （active_call_session.dart参照）。
      ref
          .read(activeCallSessionProvider.notifier)
          .startOneToOne(
            call: call,
            isCaller: false,
            callRepository: ref.read(callRepositoryProvider),
            directMessageRepository: ref.read(directMessageRepositoryProvider),
          );
    });

    return widget.child;
  }
}

final _incomingCallProvider = StreamProvider.family((ref, String userId) {
  return ref.watch(callRepositoryProvider).watchIncomingCall(userId);
});
