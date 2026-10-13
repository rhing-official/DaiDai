import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/profile_card.dart';
import '../../widgets/focal_image.dart';

/// カード上で画像の「どこを中心に見せるか」を編集するオーバーレイ
/// （2026-10-11追加）。工房のカード拡大画面（`_CardZoomEditor`）のカードの上に
/// 重ねて表示し、画面遷移はしない。ドラッグで位置、ピンチ（PCはホイール）で
/// 拡大率を変え、変更は[onChanged]で親へ通知する。キャンセル・リセット・完了の
/// ボタンはカードの外（下）に独立して置くため、このオーバーレイは持たない
/// （カード上のバッジ類と重なって操作しづらかったため、2026-10-11変更）。
///
/// [circle]がtrueならアイコン用（暗い背景の中央に円形のプレビューを出す。円は
/// カード内のアイコンと同じ正方形の枠・円形クロップなので、構図がそのまま
/// 反映される）、falseなら背景画像用（カード全面にプレビューを出す）。
class FocalEditOverlay extends StatefulWidget {
  const FocalEditOverlay({
    required this.imageUrl,
    required this.circle,
    required this.focal,
    required this.onChanged,
    super.key,
  });

  final String imageUrl;
  final bool circle;
  final ImageFocal focal;
  final void Function(ImageFocal focal) onChanged;

  @override
  State<FocalEditOverlay> createState() => _FocalEditOverlayState();
}

class _FocalEditOverlayState extends State<FocalEditOverlay> {
  Size? _imageSize;
  double _lastScale = 1;
  Offset _lastFocalPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    resolveImageSize(NetworkImage(widget.imageUrl)).then((size) {
      if (mounted && size != null) setState(() => _imageSize = size);
    });
  }

  void _apply(
    Size box, {
    Offset delta = Offset.zero,
    double scale = 1,
    Offset? anchor,
  }) {
    final image = _imageSize;
    if (image == null) return;
    widget.onChanged(
      focalAfterGesture(
        focal: widget.focal,
        box: box,
        image: image,
        delta: delta,
        scaleFactor: scale,
        anchor: anchor,
      ),
    );
  }

  /// ピンチ中心（カード内のローカル座標）を、画像を描く枠の中心からの相対位置へ。
  /// 円形（アイコン）は枠がカード中央にあるので、カード中心基準のままでよい。
  Offset _anchorFor(Offset local, Size cardSize) =>
      local - Offset(cardSize.width / 2, cardSize.height / 2);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardSize = constraints.biggest;
        final side = math.min(cardSize.width, cardSize.height) * 0.7;
        final box = widget.circle ? Size(side, side) : cardSize;
        final preview = FocalImage(url: widget.imageUrl, focal: widget.focal);
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.black),
            Center(
              child: widget.circle
                  ? SizedBox(
                      width: side,
                      height: side,
                      child: ClipOval(child: preview),
                    )
                  : preview,
            ),
            if (widget.circle)
              Center(
                child: IgnorePointer(
                  child: Container(
                    width: side,
                    height: side,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 2),
                    ),
                  ),
                ),
              ),
            // ジェスチャーは全面で受ける（ピンチ・ドラッグ・ホイール）。
            Positioned.fill(
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _apply(box, scale: math.exp(-event.scrollDelta.dy / 500));
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (details) {
                    _lastScale = 1;
                    _lastFocalPoint = details.localFocalPoint;
                  },
                  onScaleUpdate: (details) {
                    final factor = details.scale / _lastScale;
                    _lastScale = details.scale;
                    // 移動量はローカル座標（カードを縮小表示している`FittedBox`の
                    // 変換込み）で求める。画面上のpx（focalPointDelta）だと、縮小
                    // 表示のモバイルで指より画像が遅れて動いていた（2026-10-13）。
                    final delta = details.localFocalPoint - _lastFocalPoint;
                    _lastFocalPoint = details.localFocalPoint;
                    _apply(
                      box,
                      delta: delta,
                      scale: factor,
                      anchor: _anchorFor(details.localFocalPoint, cardSize),
                    );
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
