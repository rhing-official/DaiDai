import 'dart:async';

import '../../utils/screen_orientation/screen_orientation.dart';

/// 端末の向きが変わった時に[onRestart]を呼ぶ（2026-10-22）。iPadのブラウザ等では、
/// 通話中に端末を回すとカメラ映像の送信が止まる・向きが反転して相手に届くことが
/// あるため、向きが落ち着いた後にカメラを取り直す契機として使う。回転中は
/// イベントが連続するので、[settle]の間静かになってから1回だけ呼ぶ。Web以外
/// では何も起きない。
class CameraOrientationRestart {
  CameraOrientationRestart({
    required this.onRestart,
    this.settle = const Duration(milliseconds: 600),
  }) {
    _sub = screenOrientationChanges().listen((_) {
      _timer?.cancel();
      _timer = Timer(settle, onRestart);
    });
  }

  final void Function() onRestart;
  final Duration settle;
  StreamSubscription<void>? _sub;
  Timer? _timer;

  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
  }
}
