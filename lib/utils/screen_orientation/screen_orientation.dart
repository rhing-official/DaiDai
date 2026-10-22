/// 端末（ブラウザ）の画面の向きの変化を知るためのファサード（Web限定、
/// 2026-10-22追加）。通話中に端末を回した時、iPadのブラウザ等でカメラ映像の
/// 送信が止まる・上下が反転する不具合へ、カメラの取り直しで対処するために使う。
/// `dart:js_interop`はWeb以外ではコンパイルできないため、条件付きexportで
/// Web版/何もしないstub版を切り替える。
///
/// 提供するAPI:
/// - `bool get isPortraitScreen`（Webで縦向きか。Web以外は常にfalse）
/// - `Stream<void> screenOrientationChanges()`（向きが変わるたびに流れる。
///   Web以外は何も流れない）
library;

export 'screen_orientation_stub.dart'
    if (dart.library.js_interop) 'screen_orientation_web.dart';
