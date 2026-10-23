import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../utils/platform_info.dart';
import '../../widgets/nav_chip.dart';
import 'active_call_session.dart';
import 'call_avatar.dart';
import 'call_banner_card.dart';
import 'webrtc_call_controller.dart';

/// PC・Webで、一対の着信（応答前）を出すバナー（2026-10-23、以前は右上の縦長
/// ミニ表示に拒否・応答ボタンを出していた）。広場の通話開始バナー
/// （`GroupCallBannerOverlay`）と同じ位置・幅・配色の規則にそろえた。応答すると
/// 通話画面（`CallOverlay`）が今の画面の上に重なる。応答が無ければ
/// `WebrtcCallController`が[kCallRingTimeout]で不在着信として終える。
/// スマホアプリは全画面の`/call`で着信するため、このバナーは出さない。
class IncomingCallBannerOverlay extends ConsumerWidget {
  const IncomingCallBannerOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeCallSessionProvider);
    if (isMobileCallPlatform || session is! OneToOneCallSession) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: session.controller,
      builder: (context, _) {
        final controller = session.controller;
        final ringing =
            !controller.isCaller &&
            controller.state == CallConnectionState.connecting;
        if (!ringing) return const SizedBox.shrink();

        final isComputer = classifyDevice(context) == DeviceClass.computer;
        final top = MediaQuery.paddingOf(context).top + 8;
        return Positioned(
          top: top,
          left: isComputer ? kNavChipSize + kNavChipMargin * 2 + 8 : 8,
          right: isComputer ? null : 8,
          width: isComputer ? 380 : null,
          child: PointerInterceptor(
            child: _IncomingCallBanner(
              session: session,
              onDecline: controller.decline,
              onAccept: () {
                controller.accept();
                ref.read(callOverlayOpenProvider.notifier).open();
              },
              accepting: controller.accepting,
            ),
          ),
        );
      },
    );
  }
}

class _IncomingCallBanner extends ConsumerWidget {
  const _IncomingCallBanner({
    required this.session,
    required this.onDecline,
    required this.onAccept,
    required this.accepting,
  });

  final OneToOneCallSession session;
  final VoidCallback onDecline;
  final VoidCallback onAccept;
  final bool accepting;

  /// 見た目は広場の通話開始バナーと共通の[CallBannerCard]（2026-10-23統一）。
  /// 本体のタップで応答、×で拒否。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = session.call;
    final me = session.currentUserId;
    final otherId = call.otherUserId(me);
    final otherSeed = call.otherRhingSeed(me);
    return CallBannerCard(
      isVideo: call.isVideo,
      onTap: accepting ? null : onAccept,
      onClose: onDecline,
      avatarBuilder: (_) => CallParticipantAvatar(
        userId: otherId,
        rhingSeed: otherSeed,
        conversationId: call.dmId,
        radius: 20,
      ),
      titleBuilder: (style) => CallParticipantNameLabel(
        userId: otherId,
        rhingSeed: otherSeed,
        conversationId: call.dmId,
        style: style,
      ),
    );
  }
}
