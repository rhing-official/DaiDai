import 'dart:async';

/// 接続断（ICEの`disconnected`）が[grace]続いたら[onExpired]を呼ぶ小さなタイマー
/// （2026-10-13、一対の通話で、相手の回線断・端末停止時に通話が残り続けないため）。
/// 一時的な揺れで終了しないよう、回復（[update]に`false`）で解除する。
const kDisconnectedGrace = Duration(seconds: 8);

class DisconnectGrace {
  DisconnectGrace({required this.onExpired, this.grace = kDisconnectedGrace});

  final void Function() onExpired;
  final Duration grace;
  Timer? _timer;

  bool get isWaiting => _timer != null;

  /// [disconnected]がtrueの間だけ待つ。既に待機中なら延長しない。
  void update(bool disconnected) {
    if (!disconnected) {
      cancel();
      return;
    }
    _timer ??= Timer(grace, () {
      _timer = null;
      onExpired();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
