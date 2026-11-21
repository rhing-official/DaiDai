import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../models/sticker.dart';
import '../../providers/app_ui_style_provider.dart';
import 'sticker_picker_content.dart';

/// 中身を組む最小の高さ（検索欄・レール・バーが収まる高さ）。
const _kContentMinHeight = 240.0;

/// ぺったんドックの段階（閉／半分／拡大）。
enum StickerDockStage { closed, half, expanded }

/// モバイルのぺったん一覧（2026-10-29、Discord型）。モーダルのボトムシートでは
/// なく、語らい画面の本体（`Column`）の末尾＝入力欄の下に置く画面内のパネル。
/// 開いたままでもメッセージ一覧のスクロールと入力が出来る。上端のハンドルを
/// 縦にドラッグすると高さが追従し、離すと最寄りの段（閉／半分／拡大）に
/// スナップする。[StickerPickerContent]は閉じるたびに破棄せず、閉じている間は
/// 何も描かない。
class StickerPickerDock extends ConsumerWidget {
  const StickerPickerDock({
    required this.stage,
    required this.height,
    required this.bottomInset,
    required this.onStageChanged,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onStickerSelected,
    this.initialPackId,
    this.conversationKey,
    super.key,
  });

  final StickerDockStage stage;

  /// 今描く高さ（下の安全領域を含む）。親が段の高さ・ドラッグを補間して渡す
  /// （2026-11-21。親が本体の平行移動量にも同じ値を使い、跳ねずにスライドさせる）。
  final double height;

  /// 下の安全領域の高さ。
  final double bottomInset;
  final void Function(StickerDockStage stage) onStageChanged;

  /// バー・一覧の縦ドラッグ。高さの追従とスナップは親が行う。
  final void Function(double dy) onDragUpdate;
  final void Function(double velocity) onDragEnd;
  final void Function(Sticker sticker) onStickerSelected;
  final String? initialPackId;

  /// 語らい毎に直前のタブを記憶するキー（[StickerPickerContent]参照）。
  final String? conversationKey;

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
  Widget build(BuildContext context, WidgetRef ref) {
    // 完全に閉じて縮み切ったら何も描かない。閉じる途中は中身を残す。
    if (stage == StickerDockStage.closed && height <= 0.5) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    return SizedBox(
      height: height,
      child: Material(
        color: isGekiga ? colorScheme.surface : colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        // 閉じる・縮める途中で高さが中身の最小高さを下回ると下端が溢れる
        // （ピクセルエラー）ため、中身は常に一定以上の高さで組み、はみ出した
        // 分はMaterialのクリップで隠す。
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: math.max(height, _kContentMinHeight),
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) =>
                    onDragUpdate(details.delta.dy),
                onVerticalDragEnd: (details) =>
                    onDragEnd(details.primaryVelocity ?? 0),
                child: SizedBox(
                  // つまみは小さいまま、縦ドラッグを受ける当たり判定だけ広げる。
                  height: 44,
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
                    key: ValueKey(initialPackId),
                    railAxis: Axis.horizontal,
                    initialPackId: initialPackId,
                    conversationKey: conversationKey,
                    onStickerSelected: onStickerSelected,
                    // 半分の間は一覧のスクロールを止め、一覧の縦ドラッグでも
                    // バーと同じく展開・縮小する。拡大中は普通にスクロールし、
                    // 先頭からさらに下へ引くと半分へ戻る。
                    scrollLocked: stage == StickerDockStage.half,
                    onGridVerticalDragUpdate: onDragUpdate,
                    onGridVerticalDragEnd: onDragEnd,
                    onGridOverscrollTop: () {
                      if (stage == StickerDockStage.expanded) {
                        onStageChanged(StickerDockStage.half);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
