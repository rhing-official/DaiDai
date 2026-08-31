/// ブラウザ本来のFullscreen API（Web限定）を扱うためのファサード
/// （2026-08-18追加、`_MediaViewerScreenState`の`f`キー処理から使う）。
/// `dart:js_interop`はWeb以外のプラットフォームではコンパイルできないため、
/// 条件付きexportでWeb版/何もしないstub版を切り替える。
///
/// 提供するAPI:
/// - `bool get isDocumentFullscreen`
/// - `Future<void> requestDocumentFullscreen()`
/// - `Future<void> exitDocumentFullscreen()`
library;

export 'fullscreen_stub.dart'
    if (dart.library.js_interop) 'fullscreen_web.dart';
