import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../l10n/strings.dart';
import '../../providers/call_answer_providers.dart';
import '../../router/app_router.dart';
import '../../utils/platform_info.dart';
import '../../widgets/nav_chip.dart';
import 'active_call_session.dart';
import 'call_avatar.dart';
import 'call_banner_card.dart';
import 'call_log.dart';
import 'webrtc_call_controller.dart';

/// 一対の着信（応答前）を出すバナー（2026-10-23、以前は右上の縦長
/// ミニ表示に拒否・応答ボタンを出していた）。広場の通話開始バナー
/// （`GroupCallBannerOverlay`）と同じ位置・幅・配色の規則にそろえた。応答すると
/// 通話画面（`CallOverlay`）が今の画面の上に重なる。応答が無ければ
/// `WebrtcCallController`が[kCallRingTimeout]で不在着信として終える。
/// スマホアプリも同じバナーで着信を受け、応答すると全画面の`/call`へ進む
/// （2026-11-03、以前は着信と同時に全画面の2択画面を開いていた）。
const _lockChannel = MethodChannel('jp.rhing.daidai/call_action');

/// 着信の時点で、端末の画面がロックされていたか（Androidのみ。通話ごとに1回だけ調べる）。
final _lockedAtRingProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  callId,
) async {
  if (kIsWeb || !Platform.isAndroid) return false;
  try {
    return await _lockChannel.invokeMethod<bool>('isDeviceLocked') ?? false;
  } catch (_) {
    return false;
  }
});

class IncomingCallBannerOverlay extends ConsumerWidget {
  const IncomingCallBannerOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeCallSessionProvider);
    final pending = ref.watch(pendingCallAnswerProvider);
    if (session is! OneToOneCallSession) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: session.controller,
      builder: (context, _) {
        final controller = session.controller;
        final ringing =
            !controller.isCaller &&
            !controller.accepting &&
            controller.state == CallConnectionState.connecting;
        if (!ringing) {
          callLog(
            'incoming banner hidden: isCaller=${controller.isCaller} '
            'accepting=${controller.accepting} state=${controller.state} '
            'error=${controller.error}',
          );
          return const SizedBox.shrink();
        }

        void accept() {
          controller.accept();
          if (isMobileCallPlatform) {
            HapticFeedback.vibrate();
            ref
                .read(goRouterProvider)
                .push(
                  '/call',
                  extra: CallArgs(
                    call: session.call,
                    isCaller: false,
                    currentUserId: session.currentUserId,
                  ),
                );
          } else {
            ref.read(callOverlayOpenProvider.notifier).open();
          }
        }

        // 着信通知の「応答」で開かれた時は、この通話に自動で応答する（2026-11-12）。
        if (pending != null &&
            !pending.isGroup &&
            pending.callId == session.call.callId &&
            !controller.accepting) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ref.read(pendingCallAnswerProvider)?.callId !=
                session.call.callId) {
              return;
            }
            ref.read(pendingCallAnswerProvider.notifier).clear();
            accept();
          });
        }

        // ロック中の着信は、バナーではなく全画面で出す（2026-11-15）。
        final locked =
            ref.watch(_lockedAtRingProvider(session.call.callId)).value ??
            false;
        if (locked) {
          final call = session.call;
          final me = session.currentUserId;
          return Positioned.fill(
            child: PointerInterceptor(
              child: _FullScreenIncomingCall(
                userId: call.otherUserId(me),
                rhingSeed: call.otherRhingSeed(me),
                conversationId: call.dmId,
                isVideo: call.isVideo,
                onDecline: controller.decline,
                onAccept: controller.accepting ? null : accept,
              ),
            ),
          );
        }

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
              onAccept: accept,
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
      onAccept: accepting ? null : onAccept,
      onDecline: onDecline,
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

/// ロック画面で受ける着信の全画面表示（相手のアイコン・呼び名・拒否と応答の大きな丸いボタン）。
class _FullScreenIncomingCall extends ConsumerWidget {
  const _FullScreenIncomingCall({
    required this.userId,
    required this.rhingSeed,
    required this.conversationId,
    required this.isVideo,
    required this.onDecline,
    required this.onAccept,
  });

  final String userId;
  final String rhingSeed;
  final String conversationId;
  final bool isVideo;
  final VoidCallback onDecline;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    const textStyle = TextStyle(color: Colors.white);
    Widget button(Color color, IconData icon, VoidCallback? tap) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            child: Material(
              color: tap == null ? color.withValues(alpha: 0.5) : color,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: tap,
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Icon(icon, color: Colors.white, size: 34),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Material(
      color: const Color(0xFF121212),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              CallParticipantAvatar(
                userId: userId,
                rhingSeed: rhingSeed,
                conversationId: conversationId,
                radius: 64,
              ),
              const SizedBox(height: 24),
              DefaultTextStyle(
                style: textStyle.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                child: CallParticipantNameLabel(
                  userId: userId,
                  rhingSeed: rhingSeed,
                  conversationId: conversationId,
                  style: textStyle.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isVideo ? strings.callIncomingVideo : strings.callIncomingVoice,
                style: textStyle.copyWith(color: Colors.white70, fontSize: 16),
              ),
              const Spacer(flex: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  button(Colors.red.shade700, Icons.call_end, onDecline),
                  button(
                    Colors.green.shade700,
                    isVideo ? Icons.videocam : Icons.call,
                    onAccept,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
