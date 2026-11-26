import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/sticker.dart';
import '../../utils/wheel_stepper.dart';
import '../../widgets/sticker_image.dart';

/// ぺったんの拡大表示のカルーセル（2026-11-21、LINEの「おすすめスタンプ」と同じ見せ方）。
/// 選んだぺったんを中央に大きく出し、左右に隣の候補を小さく薄く覗かせる。横スワイプ・
/// ホイールで隣が中央へ来て切り替わる。中央のタップで送信、隣のタップでその候補へ寄る。
/// 提案パネル（[StickerSuggestionStrip]）と、ぺったんボタンから出すピッカーの拡大
/// プレビューで共有する（切り替えの動きを同じにする為）。ぺったんの送信方法がLINE型の
/// 時だけ使う。
class StickerCarousel extends StatefulWidget {
  const StickerCarousel({
    required this.stickers,
    required this.index,
    required this.onIndexChanged,
    required this.onSend,
    super.key,
  });

  final List<Sticker> stickers;
  final int index;
  final void Function(int index) onIndexChanged;
  final void Function(Sticker sticker) onSend;

  @override
  State<StickerCarousel> createState() => _StickerCarouselState();
}

class _StickerCarouselState extends State<StickerCarousel> {
  static const _maxSize = 320.0;
  static const _verticalPadding = 12.0;
  static const _neighbourScale = 0.55;
  static const _neighbourOpacity = 0.45;

  /// 隣のページの中心との距離（中央のぺったんの幅に対する割合）。
  static const _pageSpacing = 0.85;

  PageController? _controller;
  double _fraction = 0;

  // マウスのホイール・トラックパッドのスクロールで候補を1つずつ切り替える（2026-11-21）。
  // 細かい入力は足し合わせ、慣性で何枚も飛ばないようにする（[WheelStepper]）。
  final _wheel = WheelStepper();

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // 子（ページ）が先に受ける為、ここで受け付けると外側のスクロールに奪われない。
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final scroll = e as PointerScrollEvent;
      final delta = scroll.scrollDelta.dx.abs() > scroll.scrollDelta.dy.abs()
          ? scroll.scrollDelta.dx
          : scroll.scrollDelta.dy;
      final step = _wheel.feed(delta, DateTime.now());
      if (step == 0) return;
      final target = (widget.index + step).clamp(0, widget.stickers.length - 1);
      if (target == widget.index) return;
      _controller?.animateToPage(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// 中央のぺったんの幅に合わせて、隣が覗く`viewportFraction`でコントローラーを作る。
  /// 幅が変わった時だけ作り直す。
  PageController _ensureController(double fraction) {
    final current = _controller;
    if (current != null && (fraction - _fraction).abs() < 0.005) return current;
    _fraction = fraction;
    final next = PageController(
      initialPage: widget.index,
      viewportFraction: fraction,
    );
    _controller = next;
    if (current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return next;
  }

  @override
  void didUpdateWidget(StickerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    // 外からの切り替えにページを追従させる。
    if (controller != null &&
        controller.hasClients &&
        controller.page?.round() != widget.index) {
      controller.animateToPage(
        widget.index,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(
          constraints.maxHeight - _verticalPadding * 2,
          _maxSize,
        );
        // 隣が覗くよう、中央の幅より少し広い間隔でページを並べる。
        // 隣の中心を、中央のぺったんの幅の0.85倍だけ離して並べる。隣は0.55倍に縮むので、
        // 中央の半分（0.5）＋隣の半分（約0.275）より少し外に置けば、重ならない。
        // 離しすぎると、パネルの端の外へ出て見えなくなる。
        final pageWidth = size * _pageSpacing;
        final fraction = constraints.maxWidth <= 0
            ? 1.0
            : (pageWidth / constraints.maxWidth).clamp(0.25, 1.0);
        final controller = _ensureController(fraction);
        // ホイールは、ページが無い空白（先頭の左・末尾の右など）も含め、全体で受ける。
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: _onPointerSignal,
          child: Stack(
            children: [
              Positioned.fill(
                // マウスでも横にドラッグして切り替えられるようにする。
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                      PointerDeviceKind.stylus,
                    },
                  ),
                  child: PageView.builder(
                    controller: controller,
                    itemCount: widget.stickers.length,
                    onPageChanged: widget.onIndexChanged,
                    itemBuilder: (context, i) => AnimatedBuilder(
                      animation: controller,
                      builder: (context, child) {
                        final page =
                            controller.hasClients &&
                                controller.position.haveDimensions
                            ? (controller.page ?? widget.index.toDouble())
                            : widget.index.toDouble();
                        final delta = (page - i).abs().clamp(0.0, 1.0);
                        return Center(
                          child: Opacity(
                            opacity: 1 - (1 - _neighbourOpacity) * delta,
                            child: Transform.scale(
                              scale: 1 - (1 - _neighbourScale) * delta,
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (i == widget.index) {
                            widget.onSend(widget.stickers[i]);
                          } else {
                            controller.animateToPage(
                              i,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                        child: OverflowBox(
                          // ページの幅より大きいぺったんも、はみ出して描く。
                          maxWidth: size,
                          maxHeight: size,
                          child: SizedBox(
                            width: size,
                            height: size,
                            child: StickerImage(
                              widget.stickers[i].imageUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
