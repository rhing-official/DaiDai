import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'active_call_session.dart';
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

  /// 映像通話の間だけ、OSの自動消灯を止める（2026-11-13）。消灯すると映像が固まり、
  /// 音声の送受信も止まるため。音声通話は前面サービスで続けるので消灯してよい。
  void _syncKeepScreenOn() {
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
    session?.controllerListenable.addListener(_syncKeepScreenOn);
    _syncKeepScreenOn();
  }

  @override
  void initState() {
    super.initState();
    if (!_pipSupported) return;
    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged' && mounted) {
        ref.read(pipActiveProvider.notifier).set(call.arguments == true);
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
        final renderer = pickCallRenderer(session);
        final info = callPlaceholderInfo(session);
        return ColoredBox(
          color: Colors.black,
          child: renderer != null
              ? RTCVideoView(
                  key: ObjectKey(renderer),
                  renderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
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
