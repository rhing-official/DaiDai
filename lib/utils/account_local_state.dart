import 'package:shared_preferences/shared_preferences.dart';

/// 端末ローカルの設定のうち、アカウントを切り替えても消さないものの接頭辞。
/// パスコードロックは端末単位（アカウントに紐づかない）。
const _keepPrefixes = ['passcodeLock.'];

/// 複数アカウントの切り替えの前に、前のアカウントの端末内の状態（見た目の設定・最後に開いた
/// 寄合・最近使ったぺったんなど）を消す（2026-11-11）。消さないと、新しいアカウントでFirestoreに
/// 保存していない項目が、前のアカウントの値のまま残る。新しいアカウントの保存済みの設定は、
/// ログイン後に`applyRemoteUserPreferences`が当てる。
Future<void> clearAccountBoundLocalState() async {
  final prefs = await SharedPreferences.getInstance();
  for (final key in prefs.getKeys().toList()) {
    if (_keepPrefixes.any(key.startsWith)) continue;
    await prefs.remove(key);
  }
}
