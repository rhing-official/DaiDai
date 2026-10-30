import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// 画像・映像・PDFの拡大表示の、縦の中央・左右の端の前後矢印（2026-10-30追加）。
/// 先頭（[index] == 0）では左を、末尾（[index] == [count] - 1）では右を出さない
/// （1件だけなら両方出さない）。左は前、右は次（スワイプと同じ向き）。
class ViewerNavArrows extends StatelessWidget {
  const ViewerNavArrows({
    required this.index,
    required this.count,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final int index;
  final int count;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// 左の矢印（前へ）を出すか。
  static bool showsPrevious(int index, int count) => count > 1 && index > 0;

  /// 右の矢印（次へ）を出すか。
  static bool showsNext(int index, int count) => count > 1 && index < count - 1;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (showsPrevious(index, count))
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _ArrowButton(
                icon: Icons.chevron_left,
                onPressed: onPrevious,
              ),
            ),
          ),
        if (showsNext(index, count))
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _ArrowButton(icon: Icons.chevron_right, onPressed: onNext),
            ),
          ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Webでは映像（プラットフォームビュー）がクリックを奪うため、
    // `PointerInterceptor`で受ける。
    return PointerInterceptor(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}
