/// 端末にカメラがあるかの判定（2026-10-31追加、＋ボタンのメニューの「撮影」の
/// 出し分けに使う）。Webの`camera`パッケージの`availableCameras`は、呼ぶだけで
/// カメラの許可ダイアログが出て、カメラが無いと例外になる。許可を求めずに
/// 確認するため、Webだけブラウザのデバイス一覧を直接見る。
/// `dart:js_interop`はWeb以外でコンパイルできないため、条件付きexportで
/// Web版/それ以外（nullを返す）を切り替える。
library;

export 'camera_presence_stub.dart'
    if (dart.library.js_interop) 'camera_presence_web.dart';
