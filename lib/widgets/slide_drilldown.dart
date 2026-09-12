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
    required this.onBack,
    this.onNext,
    super.key,
  });

  final Widget master;
  final Widget? detail;
  final Object? detailKey;
  final VoidCallback onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          master,
          if (detail != null)
            Positioned.fill(
              child: _SlideInDetail(
                key: ValueKey(detailKey),
                onBack: onBack,
                onNext: onNext,
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
    required this.onBack,
    this.onNext,
    required this.child,
  });

  final VoidCallback onBack;
  final VoidCallback? onNext;
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
    return buildSlideInFromRightTransition(
      _controller,
      InteractiveSwipeBackTransition(
        onBack: widget.onBack,
        onNext: widget.onNext,
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
