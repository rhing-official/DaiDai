import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'iconSplitScale';

/// 「アイコン＋寄合一覧」の大きさの段階（2026-11-05）。1.0が従来の大きさ。視力が低い人や
/// 高齢の利用者が、アイコン列・寄合一覧の幅と文字・アイコンを大きくして使えるようにする。
const kIconSplitScaleSteps = <double>[1.0, 1.15, 1.3, 1.5, 1.75, 2.0];

/// 保存値に最も近い段階へ丸める。
double snapIconSplitScale(double value) {
  var best = kIconSplitScaleSteps.first;
  for (final step in kIconSplitScaleSteps) {
    if ((step - value).abs() < (best - value).abs()) best = step;
  }
  return best;
}

/// 端末に保存されている初期値は`main()`で起動前に読み込んで渡す（未指定のテストでは1.0）。
final initialIconSplitScaleProvider = Provider<double>((ref) => 1.0);

Future<double> loadInitialIconSplitScale() async {
  final prefs = await SharedPreferences.getInstance();
  return snapIconSplitScale(prefs.getDouble(_prefsKey) ?? 1.0);
}

/// 「アイコン＋寄合一覧」の拡大率。画面の大きさが端末ごとに違うため、端末ごとの保存のみ
/// （Firestoreには同期しない、2026-11-05）。
class IconSplitScaleNotifier extends Notifier<double> {
  @override
  double build() => ref.watch(initialIconSplitScaleProvider);

  Future<void> setScale(double scale) async {
    final snapped = snapIconSplitScale(scale);
    state = snapped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsKey, snapped);
  }
}

final iconSplitScaleProvider = NotifierProvider<IconSplitScaleNotifier, double>(
  IconSplitScaleNotifier.new,
);
