/// Web以外で、アプリ全体の状態を作り直す関数（`main.dart`が起動時に登録する、2026-11-12）。
/// 複数アカウントの切り替えの後に、前のアカウントの状態を、全て捨てるために使う。
Future<void> Function()? appRestartHook;
