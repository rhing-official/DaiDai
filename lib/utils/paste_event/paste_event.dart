/// ブラウザの`paste`イベントから貼り付けテキストを受け取るためのファサード
/// （Web限定）。`Clipboard.getData`（非同期のクリップボード読み取り）は、
/// ブラウザの権限・確認ダイアログによって`paste_fail`で失敗することがある。
/// `paste`イベントの`clipboardData`は、ユーザーの貼り付け操作そのものに
/// 付随するため権限が要らず、読み取りが拒否されたときの代替に使う。
/// `dart:js_interop`はWeb以外でコンパイルできないため、条件付きexportで
/// Web版/何もしないstub版を切り替える。
///
/// 提供するAPI:
/// - `Future<String?> readPasteEventText()`: 呼んだ直後から[timeout]の間に
///   発生した`paste`イベントのテキストを返す。貼り付けのキー入力を処理する
///   同期の区間（`await`より前）で呼ぶこと。
library;

export 'paste_event_stub.dart'
    if (dart.library.js_interop) 'paste_event_web.dart';
