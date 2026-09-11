import 'package:flutter_riverpod/flutter_riverpod.dart';

/// このアプリセッション中に、パスコードロック（`PasscodeLockGate`参照）を
/// 解除済みかどうか（2026-09-11追加）。意図的に永続化しない
/// （`SharedPreferences`/`flutter_secure_storage`に保存しない）ことで、
/// プロセスが完全に終了して再起動されるたびに`false`へ自動的に戻る。
/// これが「アプリ起動時のみロックする（バックグラウンド復帰では再ロック
/// しない）」という仕様をそのまま体現している。
class AppUnlockedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markUnlocked() => state = true;
}

final isAppUnlockedProvider = NotifierProvider<AppUnlockedNotifier, bool>(
  AppUnlockedNotifier.new,
);
