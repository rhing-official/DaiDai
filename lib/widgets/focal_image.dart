import 'dart:async';

import 'package:flutter/material.dart';

import '../models/profile_card.dart';

/// [box]いっぱいに[image]を`cover`で敷き、[focal]の拡大率・位置を反映した時の
/// 画像の描画矩形（[box]の座標系）を返す（2026-10-11追加）。
/// 拡大率1・位置(0,0)なら従来の`BoxFit.cover`＋中央と同じ。[ImageFocal.dx]/
/// [ImageFocal.dy]は`Alignment`と同じ意味で、-1で画像の左/上端が、1で右/下端が
/// [box]の端に揃う。
Rect focalImageRect({
  required Size box,
  required Size image,
  required ImageFocal focal,
}) {
  final sx = box.width / image.width;
  final sy = box.height / image.height;
  final cover = (sx > sy ? sx : sy) * focal.scale;
  final w = image.width * cover;
  final h = image.height * cover;
  return Rect.fromLTWH(
    -(w - box.width) / 2 * (1 + focal.dx),
    -(h - box.height) / 2 * (1 + focal.dy),
    w,
    h,
  );
}

/// ドラッグ（[delta]px）とピンチ・ホイール（[scaleFactor]倍）を反映した新しい
/// [ImageFocal]。指で画像をつかんで動かす感覚になるよう、画像が動く量が指の
/// 移動量と一致するように位置を換算する（画像が[box]に対して余っていない軸は
/// 動かせないので位置は変えない）。
ImageFocal focalAfterGesture({
  required ImageFocal focal,
  required Size box,
  required Size image,
  Offset delta = Offset.zero,
  double scaleFactor = 1,
}) {
  final next = focal.copyWith(scale: focal.scale * scaleFactor);
  final rect = focalImageRect(box: box, image: image, focal: next);
  final extraW = rect.width - box.width;
  final extraH = rect.height - box.height;
  return next.copyWith(
    dx: extraW > 0.5 ? next.dx - 2 * delta.dx / extraW : next.dx,
    dy: extraH > 0.5 ? next.dy - 2 * delta.dy / extraH : next.dy,
  );
}

/// 画像のピクセルサイズを取得する（フォーカル計算用）。取得に失敗したらnull。
Future<Size?> resolveImageSize(ImageProvider provider) {
  final completer = Completer<Size?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) {
        completer.complete(
          Size(info.image.width.toDouble(), info.image.height.toDouble()),
        );
      }
      stream.removeListener(listener);
    },
    onError: (_, _) {
      if (!completer.isCompleted) completer.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

/// カードの背景・円形アイコンとして画像を表示する。[focal]がnull（または既定）
/// なら従来の`BoxFit.cover`＋中央と同じ。位置が指定されている場合、画像の
/// サイズが分かるまでは`BoxFit.cover`で仮表示する。
class FocalImage extends StatefulWidget {
  const FocalImage({required this.url, this.focal, super.key});

  final String url;
  final ImageFocal? focal;

  @override
  State<FocalImage> createState() => _FocalImageState();
}

class _FocalImageState extends State<FocalImage> {
  Size? _imageSize;
  bool _resolving = false;
  late NetworkImage _provider = NetworkImage(widget.url);

  bool get _hasFocal => widget.focal != null && !widget.focal!.isDefault;

  @override
  void didUpdateWidget(FocalImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _provider = NetworkImage(widget.url);
      _imageSize = null;
    }
  }

  void _resolveSize() {
    if (_resolving) return;
    _resolving = true;
    resolveImageSize(_provider).then((size) {
      _resolving = false;
      if (mounted && size != null) setState(() => _imageSize = size);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasFocal) return Image(image: _provider, fit: BoxFit.cover);
    final size = _imageSize;
    if (size == null) {
      _resolveSize();
      return Image(image: _provider, fit: BoxFit.cover);
    }
    final focal = widget.focal!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final rect = focalImageRect(
          box: constraints.biggest,
          image: size,
          focal: focal,
        );
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: Image(image: _provider, fit: BoxFit.fill),
              ),
            ],
          ),
        );
      },
    );
  }
}
