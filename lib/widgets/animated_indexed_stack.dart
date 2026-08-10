import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// [IndexedStack]と同じく[children]を全て常駐させたまま（Stateを保持したまま）
/// [index]で表示を切り替えるが、切り替え時に[buildPopSlideTransition]と同じ
/// 「ポップ」演出を新しく選ばれた子にだけ再生する（ホーム画面のタブ切り替え、
/// `home_screen.dart`用、2026-08-10追加）。
///
/// 直前まで表示していた子は、新しい子が完全に不透明になるまでは静止したまま
/// 背後に残す（フルスクリーン画面遷移で前の画面がそのまま見えているのと
/// 同じ見た目にするため）。非表示の子は[Offstage]でレイアウト・描画自体を
/// 省く（`IndexedStack`と異なり全子を毎回レイアウトしない分、描画コストも
/// 抑えられる）。
class AnimatedIndexedStack extends StatefulWidget {
  const AnimatedIndexedStack({
    required this.index,
    required this.children,
    super.key,
  });

  final int index;
  final List<Widget> children;

  @override
  State<AnimatedIndexedStack> createState() => _AnimatedIndexedStackState();
}

class _AnimatedIndexedStackState extends State<AnimatedIndexedStack>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: popSlideDuration,
  )..value = 1;

  /// 遷移中のみ非null。新しい子のポップインが完了したら背後の描画をやめる。
  int? _previousIndex;

  @override
  void didUpdateWidget(AnimatedIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      final leaving = oldWidget.index;
      setState(() => _previousIndex = leaving);
      _controller.forward(from: 0).whenComplete(() {
        if (mounted && _previousIndex == leaving) {
          setState(() => _previousIndex = null);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildChild(int i) {
    final child = widget.children[i];
    if (i == widget.index) {
      return Offstage(
        offstage: false,
        child: buildPopSlideTransition(_controller, child),
      );
    }
    if (i == _previousIndex) {
      return Offstage(offstage: false, child: IgnorePointer(child: child));
    }
    return Offstage(offstage: true, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var i = 0; i < widget.children.length; i++) _buildChild(i),
      ],
    );
  }
}
