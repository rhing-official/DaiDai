import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'appTextSize';

/// アプリ全体の文字サイズ（2026-11-05、設定>アプリケーション）。視力が低い人や高齢の
/// 利用者が大きくして使えるようにする。小が従来の大きさ。「アイコン＋寄合一覧」の
/// アイコン列・寄合一覧の幅とアイコンも同じ倍率に連動する。
enum AppTextSize {
  small(1.0),
  medium(1.25),
  large(1.5);

  const AppTextSize(this.scale);

  final double scale;

  static AppTextSize fromName(String? name) => AppTextSize.values.firstWhere(
    (s) => s.name == name,
    orElse: () => AppTextSize.small,
  );
}

/// 端末に保存されている初期値は`main()`で起動前に読み込んで渡す（未指定のテストでは小）。
final initialAppTextSizeProvider = Provider<AppTextSize>(
  (ref) => AppTextSize.small,
);

Future<AppTextSize> loadInitialAppTextSize() async {
  final prefs = await SharedPreferences.getInstance();
  return AppTextSize.fromName(prefs.getString(_prefsKey));
}

/// 文字サイズ。画面の大きさが端末ごとに違うため、端末ごとの保存のみ
/// （Firestoreには同期しない）。
class AppTextSizeNotifier extends Notifier<AppTextSize> {
  @override
  AppTextSize build() => ref.watch(initialAppTextSizeProvider);

  Future<void> setSize(AppTextSize size) async {
    state = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, size.name);
  }
}

final appTextSizeProvider = NotifierProvider<AppTextSizeNotifier, AppTextSize>(
  AppTextSizeNotifier.new,
);
