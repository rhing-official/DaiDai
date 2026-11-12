import 'app_restart.dart';

/// Web以外では、ページの再読み込みの代わりに、アプリ全体の状態を作り直す
/// （`main.dart`の`_launchApp`、2026-11-12）。
void reloadPage() {
  appRestartHook?.call();
}
