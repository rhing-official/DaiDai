import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/home_shell_providers.dart';

/// 設定・身だしなみのトップ（項目一覧）で、横ドラッグにより隣のメニューチップのタブへ
/// 移る（2026-11-02）。ドラッグ中は`HomeScreen`が指に追従して2つのタブを横へ動かし
/// （離した時に確定）、隣はチップの表示順で決まる。項目の中へ入っている間は呼び出し側が
/// 被せる階層（右スワイプで戻る）が上に来るため、この検出は届かない。
class HomeTabSwipe extends ConsumerWidget {
  const HomeTabSwipe({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(homeTabDragControllerProvider);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) =>
          controller.onDelta?.call(details.delta.dx),
      onHorizontalDragEnd: (details) =>
          controller.onEnd?.call(details.primaryVelocity ?? 0),
      onHorizontalDragCancel: () => controller.onEnd?.call(0),
      child: child,
    );
  }
}
