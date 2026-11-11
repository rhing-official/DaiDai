/// ログイン画面に「Appleでサインイン」を出すか（2026-11-12追加）。
///
/// Apple Developer側のService ID・キーの作成と、Firebase AuthenticationのAppleプロバイダの
/// 設定（`文書/Appleデベロッパー.md`参照）は2026-11-12に済み、同日`true`にした（Webでの
/// ログイン確認は実機確認待ち）。設定が外れた場合は、押しても失敗するため`false`に戻す。
const bool kAppleSignInEnabled = true;
