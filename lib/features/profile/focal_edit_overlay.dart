import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../utils/color_hex.dart';
import '../../widgets/app_dialog.dart';

import '../../models/profile_card.dart';
import '../../widgets/focal_image.dart';

/// カード上で画像の「どこを中心に見せるか」を編集するオーバーレイ
/// （2026-10-11追加）。工房のカード拡大画面（`_CardZoomEditor`）のカードの上に
/// 重ねて表示し、画面遷移はしない。ドラッグで位置、ピンチ（PCはホイール）で
/// 拡大率を変え、変更は[onChanged]で親へ通知する。キャンセル・リセット・完了の
/// ボタンはカードの外（下）に独立して置くため、このオーバーレイは持たない
/// （カード上のバッジ類と重なって操作しづらかった為、2026-10-11変更）。
///
/// [circle]がtrueならアイコン用（暗い背景の中央に円形のプレビューを出す。円は
/// カード内のアイコンと同じ正方形の枠・円形クロップなので、構図がそのまま
/// 反映される）、falseなら背景画像用（カード全面にプレビューを出す）。
class FocalEditOverlay extends ConsumerStatefulWidget {
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
  ConsumerState<FocalEditOverlay> createState() => _FocalEditOverlayState();
}

class _FocalEditOverlayState extends ConsumerState<FocalEditOverlay> {
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
                      child: ClipOval(
                        child: ColoredBox(
                          color: widget.focal.background == null
                              ? Colors.transparent
                              : Color(widget.focal.background!),
                          child: preview,
                        ),
                      ),
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
            if (widget.circle)
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: _BackgroundPicker(
                  strings: ref.watch(appStringsProvider),
                  focal: widget.focal,
                  imageUrl: widget.imageUrl,
                  onChanged: widget.onChanged,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// アイコンの背景色の選択（2026-11-12）。透過PNGの透過部分に敷く色を、持ち主が選ぶ。
/// 左の2つは、選んだ背景でライト・ダークの面に載せた時の見え方（色が被って
/// 見えなくなっていないかの確認用）。右は色の選択肢（透明・白・黒・灰・任意）。
class _BackgroundPicker extends StatelessWidget {
  const _BackgroundPicker({
    required this.strings,
    required this.focal,
    required this.imageUrl,
    required this.onChanged,
  });

  final Strings strings;
  final ImageFocal focal;
  final String imageUrl;
  final void Function(ImageFocal focal) onChanged;

  static const _presets = [0xFFFFFFFF, 0xFF000000, 0xFF808080];

  Future<void> _pickCustom(BuildContext context) async {
    final controller = TextEditingController(
      text: focal.background == null
          ? ''
          : Color(focal.background!).toHexString(),
    );
    final picked = await showAppDialog<Color>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final parsed = tryParseHexColor(controller.text);
          return AlertDialog(
            title: Text(strings.workshopIconBackground),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '#RRGGBB'),
              onChanged: (_) => setState(() {}),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(strings.workshopFocalCancel),
              ),
              FilledButton(
                onPressed: parsed == null
                    ? null
                    : () => Navigator.of(dialogContext).pop(parsed),
                child: Text(strings.workshopFocalDone),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (picked != null) {
      onChanged(focal.copyWith(background: picked.toARGB32()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = focal.background;
    Widget swatch({
      required Color? color,
      required String tooltip,
      required bool selected,
      required VoidCallback onTap,
      Widget? child,
    }) => Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.orangeAccent : Colors.white54,
              width: selected ? 3 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
    Widget preview(Color surface) => Container(
      width: 34,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(color: surface, shape: BoxShape.circle),
      child: ClipOval(
        child: ColoredBox(
          color: current == null ? Colors.transparent : Color(current),
          child: FocalImage(url: imageUrl, focal: focal),
        ),
      ),
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            preview(Colors.white),
            preview(const Color(0xFF1E1E1E)),
            const SizedBox(width: 8),
            swatch(
              color: null,
              tooltip: strings.workshopIconBackgroundTransparent,
              selected: current == null,
              onTap: () => onChanged(focal.copyWith(clearBackground: true)),
              child: const Icon(Icons.block, size: 16, color: Colors.white70),
            ),
            for (final argb in _presets)
              swatch(
                color: Color(argb),
                tooltip: Color(argb).toHexString(),
                selected: current == argb,
                onTap: () => onChanged(focal.copyWith(background: argb)),
              ),
            swatch(
              color: null,
              tooltip: strings.workshopIconBackgroundCustom,
              selected: current != null && !_presets.contains(current),
              onTap: () => _pickCustom(context),
              child: const Icon(Icons.colorize, size: 16, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
