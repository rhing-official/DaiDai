import 'package:flutter/material.dart';

import '../theme/motion.dart';
import 'interactive_swipe_back.dart';

/// 設定・身だしなみの狭い画面ドリルダウン用。カテゴリ一覧（[master]、常時
/// マウント）の上に、選択中カテゴリの詳細（[detail]）を重ねて表示する。
/// [detail]はチャット画面と同じ「画面右外からスライドイン＋右スワイプで
/// 指追従して戻る」動きになる（[InteractiveSwipeBackTransition]をラップ）。
/// 従来の`AnimatedSwitcher`＋`SwipeBackDetector`（離散的なフェード/拡大の
/// 入れ替え）を置き換える（2026-09-12追加）。
class SlideDrilldown extends StatelessWidget {
  const SlideDrilldown({
    required this.master,
    required this.detail,
    required this.detailKey,
    this.onBack,
    this.onNext,
    this.consumeBack,
    super.key,
  });

  final Widget master;
  final Widget? detail;
  final Object? detailKey;

  /// nullなら右スワイプの「戻る」自体を付けず、スライドイン入場だけを行う
  /// （2026-10-07追加。ノートのように、[detail]側が自前で
  /// `InteractiveSwipeBackTransition`（`enabled`切替付き）を持つ場合に使う）。
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  /// 右スワイプで戻る確定の直前に呼ばれ、内側の階層を1つ閉じたら`true`を返す
  /// （外側へは戻らない、2026-10-15、設定のライセンス一覧の項目用）。
  final bool Function()? consumeBack;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 詳細を重ねている間は、裏の画面にフォーカス・キー入力を渡さない
          // （裏がフォーカスを持ったままだと、Escが前面のペインに届かない）。
          ExcludeFocus(excluding: detail != null, child: master),
          if (detail != null)
            Positioned.fill(
              child: _SlideInDetail(
                key: ValueKey(detailKey),
                onBack: onBack,
                onNext: onNext,
                consumeBack: consumeBack,
                child: detail!,
              ),
            ),
        ],
      ),
    );
  }
}

class _SlideInDetail extends StatefulWidget {
  const _SlideInDetail({
    super.key,
    this.onBack,
    this.onNext,
    this.consumeBack,
    required this.child,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final bool Function()? consumeBack;
  final Widget child;

  @override
  State<_SlideInDetail> createState() => _SlideInDetailState();
}

class _SlideInDetailState extends State<_SlideInDetail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: popSlideDuration,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onBack = widget.onBack;
    if (onBack == null) {
      return buildSlideInFromRightTransition(_controller, widget.child);
    }
    return buildSlideInFromRightTransition(
      _controller,
      InteractiveSwipeBackTransition(
        onBack: onBack,
        onNext: widget.onNext,
        consumeBack: widget.consumeBack,
        // masterへのヒットテスト透過・見た目上の欠けを防ぐため、detail全体を
        // 不透明な背景で裏打ちする（2026-09-12追加）。`ColoredBox`だと
        // detail内のListTile等がここより上にあるMaterial祖先の
        // 背景色/インク効果を隠してしまう（Flutterのアサーションで検出済み）
        // ため、それ自体がMaterial祖先になる`Material`を使う。
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: widget.child,
        ),
      ),
    );
  }
}

/// [SlideDrilldownStack]の1階層分。
class DrilldownLayer {
  const DrilldownLayer({
    required this.key,
    required this.child,
    required this.onBack,
    this.onNext,
    this.consumeBack,
  });

  /// 階層の同一性。同じキーの間は入場スライドを再生し直さず、Stateも保つ。
  final Object key;
  final Widget child;
  final VoidCallback onBack;
  final VoidCallback? onNext;
  final bool Function()? consumeBack;
}

/// [SlideDrilldown]の多階層版（2026-10-16追加）。[base]の上に[layers]を
/// 順に重ねる。[SlideDrilldown]は階層ごとに`master`/`detail`を差し替えて
/// いたため、戻ると1段上の画面が新しい`detail`として作り直され、既に
/// 見えているはずの画面が右からもう一度スライドインしていた。こちらは
/// 各階層を同じキーのまま保持し、最上位の階層を取り除くだけなので、
/// 戻った先は再演出されない。右スワイプで戻る間は直下の階層が見える。
///
/// 右スワイプで戻れるのは最上位の階層だけ（下位は`enabled: false`のまま
/// 木構造を変えず、最上位になっても子のStateが作り直されない）。
class SlideDrilldownStack extends StatelessWidget {
  const SlideDrilldownStack({
    required this.base,
    required this.layers,
    super.key,
  });

  final Widget base;
  final List<DrilldownLayer> layers;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 階層を重ねている間は、裏の画面にフォーカス・キー入力を渡さない
          // （[SlideDrilldown]と同じ理由）。
          ExcludeFocus(excluding: layers.isNotEmpty, child: base),
          for (var i = 0; i < layers.length; i++)
            Positioned.fill(
              key: ValueKey(layers[i].key),
              child: ExcludeFocus(
                excluding: i != layers.length - 1,
                child: _StackLayer(
                  isTop: i == layers.length - 1,
                  layer: layers[i],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StackLayer extends StatefulWidget {
  const _StackLayer({required this.isTop, required this.layer});

  final bool isTop;
  final DrilldownLayer layer;

  @override
  State<_StackLayer> createState() => _StackLayerState();
}

class _StackLayerState extends State<_StackLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: popSlideDuration,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    return buildSlideInFromRightTransition(
      _controller,
      InteractiveSwipeBackTransition(
        enabled: widget.isTop,
        onBack: layer.onBack,
        onNext: layer.onNext,
        consumeBack: layer.consumeBack,
        // 直下の階層へのヒットテスト透過・見た目上の欠けを防ぐため、不透明な
        // `Material`で裏打ちする（[_SlideInDetail]と同じ）。
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: layer.child,
        ),
      ),
    );
  }
}
