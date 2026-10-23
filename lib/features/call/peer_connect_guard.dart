/// 広場通話で、同じ相手への接続処理（`_connectToPeer`）が重複して走らないように
/// する印（2026-10-23）。接続処理はTURN認証情報の取得などで数秒かかり、その間に
/// 届く次の参加者スナップショットが同じ相手へもう一度接続を始めてしまい、
/// PeerConnection・レンダラーが二重にできて映像が届かなくなっていた。
class PeerConnectGuard {
  final Set<String> _active = {};
  final Set<String> _cancelled = {};

  /// 接続処理を始めてよければ`true`（既に同じ相手の接続処理が走っていれば`false`）。
  bool tryBegin(String userId) {
    if (!_active.add(userId)) return false;
    _cancelled.remove(userId);
    return true;
  }

  /// 接続処理が終わった（成功・失敗とも）。
  void end(String userId) {
    _active.remove(userId);
    _cancelled.remove(userId);
  }

  /// 接続処理の途中で相手が退室した等で、続けても無駄になった。
  void cancel(String userId) {
    if (_active.contains(userId)) _cancelled.add(userId);
  }

  void cancelAll() => _cancelled.addAll(_active);

  bool isCancelled(String userId) => _cancelled.contains(userId);

  bool isConnecting(String userId) => _active.contains(userId);
}
