import 'package:flutter/material.dart';

/// ホーム画面の形をした読み込み中のスケルトン（2026-11-12）。アカウントの追加・切り替えの
/// 直後に、住人データを読み込む間、読み込みが進んでいることが分かるように出す。
/// 色は文字色の薄い塗りで、UIスタイル・ライト/ダークに依らず使える。ゆっくり明滅する。
class HomeSkeleton extends StatefulWidget {
  const HomeSkeleton({super.key});

  @override
  State<HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<HomeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final color = base.withValues(
              alpha: 0.06 + 0.07 * _controller.value,
            );
            Widget block(double w, double h, {double radius = 8}) => Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(radius),
              ),
            );
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  block(120, 22),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.separated(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 8,
                      separatorBuilder: (_, _) => const SizedBox(height: 18),
                      itemBuilder: (_, i) => Row(
                        children: [
                          block(48, 48, radius: 24),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                block(110 + (i % 3) * 30, 14),
                                const SizedBox(height: 8),
                                block(200 + (i % 2) * 40, 12),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        block(72, 40, radius: 20),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
