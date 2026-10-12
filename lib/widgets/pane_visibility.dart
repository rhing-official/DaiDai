import 'package:flutter/widgets.dart';

/// 子孫が「実際に画面に見えているか」を知るための印（2026-10-13追加）。
/// `IndexedStack`は非選択の子もマウントしたままで、`TickerMode`も無効にしない
/// ため、語らいタブの詳細ペインやホームのタブのように`IndexedStack`で保持される
/// 子は、見えていなくても「表示中」と誤認されうる。通話画面の埋め込み表示
/// （`EmbeddedCallPane`）が、見えている間だけ右上のミニ表示を隠すために使う。
///
/// 入れ子にした場合は親の[visible]との論理積になる（外側が隠れていれば内側も
/// 隠れている）。包まれていない場所では[of]は`true`。
class PaneVisibility extends StatelessWidget {
  const PaneVisibility({required this.visible, required this.child, super.key});

  final bool visible;
  final Widget child;

  /// [context]の位置が見えているか（祖先の[PaneVisibility]すべてが`true`なら`true`）。
  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_PaneVisibilityScope>()
            ?.visible ??
        true;
  }

  @override
  Widget build(BuildContext context) {
    return _PaneVisibilityScope(visible: visible && of(context), child: child);
  }
}

class _PaneVisibilityScope extends InheritedWidget {
  const _PaneVisibilityScope({required this.visible, required super.child});

  final bool visible;

  @override
  bool updateShouldNotify(_PaneVisibilityScope oldWidget) =>
      oldWidget.visible != visible;
}
