import 'package:flutter/material.dart';

/// スワイプジェスチャーを「切り替え」ではなく「戻る／閉じる」操作として
/// 扱うための共通しきい値・ラッパー（2026-07-25）。
/// 以前はホーム画面全体を覆うジェスチャーで4タブ（語らい/身だしなみ/設定/運営）を
/// 切り替えていたが、ポップアップ等のオーバーレイ上ではバリアがジェスチャーを
/// 吸収してしまい一貫して動作しなかったため廃止し、代わりに各画面が持つ
/// 「戻る」操作（設定・身だしなみ・運営タブの狭い画面でのカテゴリ一覧への
/// ドリルダウン、go_routerでpushした各画面のpop）に個別にスワイプを割り当てる。
const kSwipeGestureVelocityThreshold = 150.0;

/// 右方向への横スワイプで[onBack]を呼ぶ。
class SwipeBackDetector extends StatelessWidget {
  const SwipeBackDetector({required this.onBack, required this.child, super.key});

  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity >= kSwipeGestureVelocityThreshold) onBack();
      },
      child: child,
    );
  }
}

/// 下方向への縦スワイプで[onDismiss]を呼ぶ。ポップアップ（Dialog）を
/// 下にスライドして閉じる操作に使う。
class SwipeDownToDismiss extends StatelessWidget {
  const SwipeDownToDismiss({required this.onDismiss, required this.child, super.key});

  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity >= kSwipeGestureVelocityThreshold) onDismiss();
      },
      child: child,
    );
  }
}
