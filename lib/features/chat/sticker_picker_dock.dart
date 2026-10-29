import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../models/sticker.dart';
import '../../providers/app_ui_style_provider.dart';
import 'sticker_picker_content.dart';

/// ぺったんドックの段階（閉／半分／拡大）。
enum StickerDockStage { closed, half, expanded }

/// モバイルのぺったん一覧（2026-10-29、Discord型）。モーダルのボトムシートでは
/// なく、語らい画面の本体（`Column`）の末尾＝入力欄の下に置く画面内のパネル。
/// 開いたままでもメッセージ一覧のスクロールと入力ができる。上端のハンドルを
/// 縦にドラッグすると高さが追従し、離すと最寄りの段（閉／半分／拡大）に
/// スナップする。[StickerPickerContent]は閉じるたびに破棄せず、閉じている間は
/// 何も描かない。
class StickerPickerDock extends ConsumerStatefulWidget {
  const StickerPickerDock({
    required this.stage,
    required this.onStageChanged,
    required this.onStickerSelected,
    this.initialPackId,
    super.key,
  });

  final StickerDockStage stage;
  final void Function(StickerDockStage stage) onStageChanged;
  final void Function(Sticker sticker) onStickerSelected;
  final String? initialPackId;

  /// 半分の高さ（画面高の約40%、260〜420）。
  static double halfHeight(double screenHeight) =>
      (screenHeight * 0.4).clamp(260.0, 420.0);

  /// 拡大の高さ（画面高の約85%）。上にヘッダーが見える程度。
  static double expandedHeight(double screenHeight) => screenHeight * 0.85;

  /// 縦ドラッグ後の高さ[height]と指を離した時の速度[velocity]（下向きが正、
  /// px/s）から、スナップ先の段を決める。
  static StickerDockStage snap({
    required double height,
    required double velocity,
    required double screenHeight,
  }) {
    final half = halfHeight(screenHeight);
    final expanded = expandedHeight(screenHeight);
    if (velocity < -700) {
      return height < half ? StickerDockStage.half : StickerDockStage.expanded;
    }
    if (velocity > 700) {
      return height > half ? StickerDockStage.half : StickerDockStage.closed;
    }
    final targets = {
      StickerDockStage.closed: 0.0,
      StickerDockStage.half: half,
      StickerDockStage.expanded: expanded,
    };
    return targets.entries
        .reduce(
          (a, b) =>
              (a.value - height).abs() <= (b.value - height).abs() ? a : b,
        )
        .key;
  }

  @override
  ConsumerState<StickerPickerDock> createState() => _StickerPickerDockState();
}

class _StickerPickerDockState extends ConsumerState<StickerPickerDock> {
  // ドラッグ中の高さ（nullなら段の高さに従う）。
  double? _dragHeight;

  double _stageHeight(double screenHeight) => switch (widget.stage) {
    StickerDockStage.closed => 0,
    StickerDockStage.half => StickerPickerDock.halfHeight(screenHeight),
    StickerDockStage.expanded => StickerPickerDock.expandedHeight(screenHeight),
  };

  @override
  Widget build(BuildContext context) {
    if (widget.stage == StickerDockStage.closed) {
      return const SizedBox.shrink();
    }
    final screenHeight = MediaQuery.sizeOf(context).height;
    final colorScheme = Theme.of(context).colorScheme;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final height = _dragHeight ?? (_stageHeight(screenHeight) + bottomInset);

    return AnimatedContainer(
      duration: _dragHeight == null
          ? const Duration(milliseconds: 180)
          : Duration.zero,
      curve: Curves.easeOut,
      height: height,
      child: Material(
        color: isGekiga ? colorScheme.surface : colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                final max =
                    StickerPickerDock.expandedHeight(screenHeight) +
                    bottomInset;
                setState(
                  () =>
                      _dragHeight = (height - details.delta.dy).clamp(0.0, max),
                );
              },
              onVerticalDragEnd: (details) {
                final dragged = (_dragHeight ?? height) - bottomInset;
                final stage = StickerPickerDock.snap(
                  height: math.max(0, dragged),
                  velocity: details.primaryVelocity ?? 0,
                  screenHeight: screenHeight,
                );
                setState(() => _dragHeight = null);
                widget.onStageChanged(stage);
              },
              child: SizedBox(
                height: 28,
                width: double.infinity,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: StickerPickerContent(
                  key: ValueKey(widget.initialPackId),
                  railAxis: Axis.horizontal,
                  initialPackId: widget.initialPackId,
                  onStickerSelected: widget.onStickerSelected,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
