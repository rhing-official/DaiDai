/// ブラウザのタブを閉じる・離れる時に呼ばれる処理を登録するファサード（Web限定、
/// 2026-10-31追加）。広場通話で、タブを閉じても参加者として残り続けないよう、
/// 退出の書き込みを試みるために使う（ベストエフォート。書き込みの完了までは
/// 保証されないので、在室確認の失効が最終的な後始末になる）。`package:web`は
/// Web以外ではコンパイルできないため、条件付きexportでWeb版/何もしないstub版を
/// 切り替える。
///
/// 提供するAPI:
/// - `void Function() onPageExit(void Function() callback)`（登録を解除する関数を返す）
library;

export 'page_exit_stub.dart' if (dart.library.js_interop) 'page_exit_web.dart';
