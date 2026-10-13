import 'package:flutter/widgets.dart';

/// OSの「アニメーション効果オフ」（視覚効果の軽減・`prefers-reduced-motion`）を
/// 無視して、アプリ内の全ての`AnimationController`を通常の所要時間で動かす
/// バインディング（2026-10-13、ユーザー指示）。
///
/// 画面遷移・`Switch`・暗黙的アニメーション等の`AnimationController`は、
/// `MediaQuery`ではなく`SemanticsBinding.disableAnimations`を直接参照し、真だと
/// 所要時間を5%にして一瞬で終わらせる。`MediaQuery`の上書き
/// （`AlwaysAnimations`）ではこれを止められないため、ここで常に偽にする。
/// OSの設定自体は変えない（アプリ内の読み取り値だけを上書きする）。
class AlwaysAnimateBinding extends WidgetsFlutterBinding {
  AlwaysAnimateBinding();

  static AlwaysAnimateBinding? _instance;

  /// `WidgetsFlutterBinding.ensureInitialized()`の代わりに`main()`の最初で呼ぶ。
  static WidgetsBinding ensureInitialized() {
    _instance ??= AlwaysAnimateBinding();
    return WidgetsBinding.instance;
  }

  @override
  bool get disableAnimations => false;
}
