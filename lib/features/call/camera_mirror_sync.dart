import 'dart:async';

/// [MirrorSyncRace]の既定のフォールバック待ち時間。2026-11-16の対策の値を
/// 引き継ぐ（実機で厳密に測った値ではないが、保証のない信号が来なかった時の
/// 保険として残す。信号が来ればそれより早く確定する）。
const kMirrorSyncFallback = Duration(milliseconds: 450);

/// 送信中の映像のフレーム数の増加を合図にできる時の、保険の時間（2026-11-25）。実機（Android）では、
/// カメラを切り替えた後、新しいカメラの映像が0.5秒以上届かず、その間は切り替え前の画像が止まって
/// 見える。450msで反転を切り替えると、止まった古い画像が左右反転して見えるため、新しい最初の
/// フレームが出るまで待つ。合図が来ない時の最後の保険。
const kMirrorFrameWaitFallback = Duration(milliseconds: 3000);

/// カメラ切替後、「反転をいつ切り替えるか」を複数の非同期シグナルの競走で
/// 決める小さなクラス（2026-11-23）。
///
/// 固定タイマーだけで決めていた従来実装は、端末によって新しいカメラの最初の
/// フレームが届くタイミングがずれ、「一瞬だけ古い映像に新しい反転がかかって
/// 左右反転して見える」不具合の再発につながった（2026-11-16に一度対策、450msは
/// 実機で決めた値ではないとの注記が既存コードに残っていた）。
///
/// `RTCVideoRenderer`の`onResize`（実際に届いたフレームの解像度・回転が
/// 変わった時に発火）・`onFirstFrameRendered`のどちらかが先に発火すれば
/// それを使い、どちらも発火しなければ[fallback]経過後に確定させる。
///
/// 注記（third_party/flutter_webrtcの実装を確認した上での既知の限界）:
/// Web実装は`onFirstFrameRendered`を一度も呼ばない（未実装）。ネイティブ実装は
/// `Helper.switchCamera`がトラックを差し替えない為、`didFirstFrameRendered`は
/// 通話開始時に既に消費済みで切替時には再発火しない。実質的に効くのは
/// `onResize`で、前面/背面カメラの解像度・回転メタデータが端末によって同一の
/// 場合はそれも発火せず、[fallback]が唯一の確定手段になる。
class MirrorSyncRace {
  MirrorSyncRace({this.fallback = kMirrorSyncFallback});

  final Duration fallback;

  Timer? _timer;
  bool _settled = true;

  bool get isPending => !_settled;

  /// 競走を開始する。[onSettle]は、どの経路で確定しても一度だけ呼ばれる。
  /// 既に別の競走が進行中なら、確定させずに止めてから新しく始める（連打対策）。
  ///
  /// [fallbackOverride]を渡すと、その回だけ保険の時間を変える（フレーム数の合図を待てる時は
  /// 長く待つ、2026-11-25）。
  void start(void Function() onSettle, {Duration? fallbackOverride}) {
    cancel();
    _settled = false;
    void settle() {
      if (_settled) return;
      _settled = true;
      _timer?.cancel();
      _timer = null;
      onSettle();
    }

    signalResize = settle;
    signalFirstFrame = settle;
    signalFrame = settle;
    _timer = Timer(fallbackOverride ?? fallback, settle);
  }

  /// `RTCVideoRenderer.onResize`/`onFirstFrameRendered`に直接代入して使う
  /// 差し込み口。
  void Function()? signalResize;
  void Function()? signalFirstFrame;

  /// 送信している映像のフレーム数が増えた（新しいカメラの最初のフレームが出た）時に呼ぶ
  /// （2026-11-25）。端末によっては前面・背面で解像度も向きも同じで、`onResize`も
  /// `onFirstFrameRendered`も発火せず、[fallback]が唯一の確定手段になり、それが遅くて
  /// 反転して見えていた（実機のログで確認）。
  void Function()? signalFrame;

  /// 進行中の競走を、確定させずに止める（dispose・次の切替開始時）。
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _settled = true;
    signalResize = null;
    signalFirstFrame = null;
    signalFrame = null;
  }
}
