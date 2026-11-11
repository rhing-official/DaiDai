/// ブラウザのページを再読み込みするファサード（Web限定、2026-11-11）。複数アカウントの
/// 切り替えで、前のアカウントの状態をアプリ全体から確実に消すために使う。`package:web`は
/// Web以外ではコンパイルできないので、条件付きexportでWeb版/何もしないstub版を切り替える。
///
/// 提供するAPI: `void reloadPage()`
library;

export 'page_reload_stub.dart'
    if (dart.library.js_interop) 'page_reload_web.dart';
