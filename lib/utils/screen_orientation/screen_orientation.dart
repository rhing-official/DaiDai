/// 端末（ブラウザ）の画面が縦向きかを知るためのファサード（Web限定、2026-10-22追加）。
/// 通話の映像制約（`buildVideoConstraints`）が、縦向きの時に縦長の解像度・比率を
/// 要求するために使う。`dart:js_interop`はWeb以外ではコンパイルできないため、
/// 条件付きexportでWeb版/何もしないstub版を切り替える。
///
/// 提供するAPI:
/// - `bool get isPortraitScreen`（Webで縦向きか。Web以外は常にfalse）
///
/// 以前あった向きの変化の通知（`screenOrientationChanges`）は、向きが変わった後に
/// カメラを取り直す処理のためのものだったが、取り直すと映像が横長に戻る不具合に
/// なったため、その処理ごと廃止した（2026-10-23）。
library;

export 'screen_orientation_stub.dart'
    if (dart.library.js_interop) 'screen_orientation_web.dart';
