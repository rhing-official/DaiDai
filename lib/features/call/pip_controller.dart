import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../providers/call_display_provider.dart';
import 'active_call_session.dart';
import 'call_log.dart';
import 'call_avatar.dart';
import 'pinned_call_overlay.dart';

/// Android（アプリ版）のピクチャーインピクチャー（PiP）中かどうか
/// （2026-10-12追加）。アプリを離れた時、通話中ならOS標準の小窓に通話の
/// 映像だけを残す。iOS・デスクトップ・Webは対象外。
class PipActiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final pipActiveProvider = NotifierProvider<PipActiveNotifier, bool>(
  PipActiveNotifier.new,
);

const _pipChannel = MethodChannel('jp.rhing.daidai/pip');

bool get _pipSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// 戻るボタンで、OS標準のピクチャーインピクチャーに入る（2026-11-16）。入れたら`true`。
/// Android以外・非対応の端末・入れなかった時は`false`（呼び出し側は、アプリ内のミニ表示にする）。
Future<bool> enterCallPip() async {
  if (!_pipSupported) return false;
  try {
    final ok = await _pipChannel.invokeMethod<bool>('enterPip');
    callLog('PiP: enterPip requested ok=$ok');
    return ok ?? false;
  } catch (e) {
    callLog('PiP: enterPip failed: $e');
    return false;
  }
}

/// 通話の有無をネイティブ（`MainActivity`）へ伝え、PiPの出入りを
/// [pipActiveProvider]へ反映する。アプリ全体の上位に1つ置く。PiP中は
/// 通話の映像を画面いっぱいに重ねて表示する（PiPの小窓はアプリ全体の
/// 縮小表示の為）。
class PipHost extends ConsumerStatefulWidget {
  const PipHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PipHost> createState() => _PipHostState();
}

class _PipHostState extends ConsumerState<PipHost> {
  ActiveCallSession? _watchedSession;
  bool _keepScreenOn = false;
  bool? _sentPipAllowed;

  /// アプリを離れた時・戻るでOS標準のPiPへ入ってよいかをネイティブへ伝える（2026-11-18、
  /// 設定の方針＋映像の有無）。入ってはいけない時は、ネイティブはPiPに入らず、アプリ内の
  /// ミニ表示（設定に従う）になる。
  void _syncPipAllowed() {
    final session = _watchedSession;
    final hasVideo =
        session != null &&
        (session.isVideoLocallyOn || session.hasAnyRemoteVideoOn);
    final allowed = callPipAllowed(
      ref.read(callPipPolicyProvider),
      hasVideo: hasVideo,
    );
    if (allowed == _sentPipAllowed) return;
    _sentPipAllowed = allowed;
    _invoke('setPipAllowed', {'allowed': allowed});
  }

  /// 映像通話の間だけ、OSの自動消灯を止める（2026-11-13）。消灯すると映像が固まり、
  /// 音声の送受信も止まるため。音声通話は前面サービスで続けるので消灯してよい。
  void _syncKeepScreenOn() {
    _syncPipAllowed();
    final session = _watchedSession;
    final keep =
        session != null &&
        (session.isVideoLocallyOn || session.hasAnyRemoteVideoOn);
    if (keep == _keepScreenOn) return;
    _keepScreenOn = keep;
    _invoke('setKeepScreenOn', {'keep': keep});
  }

  void _watchSession(ActiveCallSession? session) {
    _watchedSession?.controllerListenable.removeListener(_syncKeepScreenOn);
    _watchedSession = session;
    _sentPipAllowed = null;
    session?.controllerListenable.addListener(_syncKeepScreenOn);
    _syncKeepScreenOn();
  }

  @override
  void initState() {
    super.initState();
    if (!_pipSupported) return;
    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged' && mounted) {
        callLog('PiP: changed to ${call.arguments}');
        ref.read(pipActiveProvider.notifier).set(call.arguments == true);
      } else if (call.method == 'micSilenced' && mounted) {
        // 他のアプリ（別の通話など）にマイクを奪われ、OSが自分のマイクを無音にした／戻った。
        final silenced = call.arguments == true;
        callLog('mic unavailable (native): $silenced');
        switch (ref.read(activeCallSessionProvider)) {
          case OneToOneCallSession(:final controller):
            controller.setMicUnavailable(silenced);
          case GroupCallSession(:final controller):
            controller.setMicUnavailable(silenced);
          default:
            break;
        }
      } else if (call.method == 'screenShareStopped' && mounted) {
        // 共有していたアプリが閉じられた等で、画面共有の元が終わった。共有も終える。
        callLog('screen share source ended natively; stopping the share');
        switch (ref.read(activeCallSessionProvider)) {
          case OneToOneCallSession(:final controller):
            await controller.stopScreenShare();
          case GroupCallSession(:final controller):
            await controller.stopScreenShare();
          default:
            break;
        }
      } else if (call.method == 'pipDismissed' && mounted) {
        // PiPの小窓を×で閉じた。通話を続けると落ちるため、終了する。
        callLog('PiP window dismissed; ending the call');
        await ref.read(activeCallSessionProvider.notifier).endCall();
      }
    });
  }

  @override
  void dispose() {
    if (_pipSupported) {
      _watchedSession?.controllerListenable.removeListener(_syncKeepScreenOn);
      _watchedSession = null;
      if (_keepScreenOn) _invoke('setKeepScreenOn', {'keep': false});
      _pipChannel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  Future<void> _setCallActive(bool active) =>
      _invoke('setCallActive', {'active': active});

  Future<void> _invoke(String method, Map<String, Object?> args) async {
    try {
      await _pipChannel.invokeMethod<void>(method, args);
    } on PlatformException {
      // PiP非対応の端末等。通話自体には影響しないため無視する。
    } on MissingPluginException {
      // ネイティブ側が未登録（テスト・非Android）の場合も無視する。
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_pipSupported) return widget.child;

    ref.listen(callPipPolicyProvider, (_, _) => _syncPipAllowed());
    ref.listen(activeCallSessionProvider, (previous, next) {
      final wasActive = previous != null;
      final isActive = next != null;
      if (wasActive != isActive) _setCallActive(isActive);
      if (!identical(previous, next)) _watchSession(next);
      if (!isActive) ref.read(pipActiveProvider.notifier).set(false);
    });

    final session = ref.watch(activeCallSessionProvider);
    final pipActive = ref.watch(pipActiveProvider);
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (pipActive && session != null)
          Positioned.fill(child: _PipCallView(session: session)),
      ],
    );
  }
}

/// PiPの小窓に表示する、通話の映像（無ければ相手のアバター）。操作ボタンは
/// 出さない（拡大・閉じるはOS標準の操作）。
class _PipCallView extends StatelessWidget {
  const _PipCallView({required this.session});

  final ActiveCallSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session.controllerListenable,
      builder: (context, _) {
        final content = pickPipContent(session);
        final renderer = content.renderer;
        final info = callPlaceholderInfo(session);
        return ColoredBox(
          color: Colors.black,
          child: renderer != null
              ? RTCVideoView(
                  key: ObjectKey(renderer),
                  renderer,
                  objectFit: content.isScreen
                      ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                      : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : Center(
                  child: CallParticipantAvatar(
                    userId: info.userId,
                    rhingSeed: info.rhingSeed,
                    conversationId: info.conversationId,
                    radius: 36,
                    fontSize: 28,
                  ),
                ),
        );
      },
    );
  }
}
