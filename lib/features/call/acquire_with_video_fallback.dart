/// カメラ・マイクを取得する。映像を求められた（[wantVideo]）が取得できなければ
/// （カメラが無い・許可されない端末）、**音声のみ**でもう一度取得する（2026-10-23）。
/// 通話の音声/映像の種別は開始者の希望にすぎず、始めた後は各自が映像を切り替えられる
/// ため、カメラが使えないことで参加できなくなるのを避ける。音声のみでも失敗したら
/// 例外をそのまま投げる。戻り値の`usedVideo`は、実際に映像を取得できたか。
Future<({T stream, bool usedVideo})> acquireWithVideoFallback<T>({
  required bool wantVideo,
  required Future<T> Function(bool video) acquire,
}) async {
  if (!wantVideo) return (stream: await acquire(false), usedVideo: false);
  try {
    return (stream: await acquire(true), usedVideo: true);
  } catch (_) {
    return (stream: await acquire(false), usedVideo: false);
  }
}
