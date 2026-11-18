import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../models/call.dart';
import '../../providers/call_answer_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/ring_launch_provider.dart';
import 'active_call_session.dart';
import 'call_log.dart';
import 'call_ring_timeout.dart';
import 'incoming_call_banner.dart';

const _channel = MethodChannel('jp.rhing.daidai/call_action');

/// 着信の全画面インテント（Androidの着信通知、スリープ・ロック中）でアプリが開かれた時に、
/// 通話のセッションが始まる（Firestoreの着信を検知する）のを待たず、通知に載せた情報で、すぐ
/// 全画面の応答/拒否を出す層（2026-11-18）。待つ間、アプリの前回の画面が見えていたのを防ぐ。
/// セッションが同じ通話で始まったら、一対は[IncomingCallBannerOverlay]、広場は通常の通話開始の
/// 表示へ引き継ぐ。
class RingLaunchOverlay extends ConsumerStatefulWidget {
  const RingLaunchOverlay({super.key});

  @override
  ConsumerState<RingLaunchOverlay> createState() => _RingLaunchOverlayState();
}

class _RingLaunchOverlayState extends ConsumerState<RingLaunchOverlay> {
  Timer? _timeout;
  String? _timeoutFor;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    _takePending();
  }

  /// アプリが起動した時に溜まっている着信の情報（早い段階で、ログイン前でも受け取る）。
  Future<void> _takePending() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final pending = await _channel.invokeMethod<Object?>('takePendingRing');
      final ring = RingLaunch.fromChannel(pending);
      if (ring != null && mounted) {
        ref.read(ringLaunchProvider.notifier).set(ring);
      }
    } on MissingPluginException {
      // 想定外の環境。何もしない。
    } on PlatformException {
      // 同上。
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  /// 通話のセッションが始まらないまま呼び出しの時間が過ぎたら（発信側が先に切った等）、閉じる。
  void _armTimeout(RingLaunch ring) {
    if (_timeoutFor == ring.callId) return;
    _timeout?.cancel();
    _timeoutFor = ring.callId;
    _answered = false;
    _timeout = Timer(kCallRingTimeout + const Duration(seconds: 5), () {
      if (!mounted) return;
      if (ref.read(ringLaunchProvider)?.callId == ring.callId) {
        callLog('ring launch: timed out without a session');
        ref.read(ringLaunchProvider.notifier).clear();
      }
    });
  }

  bool _takenOver(RingLaunch ring, ActiveCallSession? session) {
    if (session is OneToOneCallSession) {
      return session.call.callId == ring.callId;
    }
    if (session is GroupCallSession) {
      return session.groupCallId == ring.callId;
    }
    return false;
  }

  void _accept(RingLaunch ring) {
    setState(() => _answered = true);
    // セッションが始まり次第、既存の仕組み（着信通知の「応答」と同じ）が自動で応答する。
    ref
        .read(pendingCallAnswerProvider.notifier)
        .set(
          PendingCallAnswer(
            kind: ring.kind,
            callId: ring.callId,
            groupId: ring.groupId,
          ),
        );
  }

  void _decline(RingLaunch ring) {
    if (!ring.isGroup) {
      // セッションが無いまま拒否する時は、通話の状態を直接書き換える。
      ref
          .read(callRepositoryProvider)
          .updateStatus(ring.callId, CallStatus.declined)
          .catchError((_) {});
    }
    ref.read(ringLaunchProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final ring = ref.watch(ringLaunchProvider);
    final session = ref.watch(activeCallSessionProvider);
    if (ring == null) {
      _timeoutFor = null;
      return const SizedBox.shrink();
    }
    _armTimeout(ring);
    // 同じ通話のセッションが始まったら、そちらの表示へ引き継ぐ。
    if (_takenOver(ring, session)) return const SizedBox.shrink();
    return Positioned.fill(
      child: PointerInterceptor(
        child: IncomingCallFullScreen(
          avatar: _RingAvatar(name: ring.callerName, iconUrl: ring.iconUrl),
          title: Text(
            ring.callerName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          isVideo: ring.isVideo,
          onDecline: () => _decline(ring),
          onAccept: _answered ? null : () => _accept(ring),
        ),
      ),
    );
  }
}

/// 通知に載っていたアイコンと呼び名から作る、相手のアイコン（半径64）。
class _RingAvatar extends StatelessWidget {
  const _RingAvatar({required this.name, required this.iconUrl});

  final String name;
  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    final url = iconUrl;
    return CircleAvatar(
      radius: 64,
      backgroundColor: Colors.grey.shade800,
      foregroundImage: url == null || url.isEmpty ? null : NetworkImage(url),
      child: Text(
        name.isEmpty ? '?' : name.characters.first,
        style: const TextStyle(color: Colors.white, fontSize: 44),
      ),
    );
  }
}
