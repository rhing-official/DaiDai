import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/profile_card.dart';
import '../../widgets/focal_image.dart';

/// 選んだ画像のうち、アイコンに使う範囲を円形の枠の中で選ぶダイアログ
/// （2026-11-07追加、お便りのアイコン用）。ドラッグで位置、ピンチ（PCはホイール）で
/// 拡大率を変え、「決定」で正方形にトリミングしたPNGのバイト列を返す
/// （キャンセルならnull）。位置・拡大率の計算は[focalAfterGesture]を再利用。
Future<Uint8List?> showIconCropDialog(
  BuildContext context,
  Uint8List imageBytes,
) {
  return showDialog<Uint8List>(
    context: context,
    builder: (_) => IconCropDialog(imageBytes: imageBytes),
  );
}

/// [image]（画像のピクセル寸法）を[focal]の構図で[size]四方に描いた時の、
/// 元画像上の描画矩形。トリミング結果の描画先の計算を、テストできる形で切り出した。
Rect iconCropDestRect({
  required Size image,
  required ImageFocal focal,
  required double size,
}) => focalImageRect(box: Size(size, size), image: image, focal: focal);

/// [bytes]を[focal]の構図で[size]四方にトリミングし、PNGで返す。
Future<Uint8List> cropIconToPng({
  required ui.Image source,
  required ImageFocal focal,
  int size = 512,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final dest = iconCropDestRect(
    image: Size(source.width.toDouble(), source.height.toDouble()),
    focal: focal,
    size: size.toDouble(),
  );
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    dest,
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

class IconCropDialog extends StatefulWidget {
  const IconCropDialog({required this.imageBytes, super.key});

  final Uint8List imageBytes;

  @override
  State<IconCropDialog> createState() => _IconCropDialogState();
}

class _IconCropDialogState extends State<IconCropDialog> {
  static const _side = 280.0;

  ui.Image? _image;
  late Uint8List _bytes = widget.imageBytes;
  ImageFocal _focal = ImageFocal.center;
  double _lastScale = 1;
  Offset _lastPoint = Offset.zero;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load(_bytes);
  }

  Future<void> _load(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _image = frame.image;
        _focal = ImageFocal.center;
      });
    }
  }

  Future<void> _changeImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    _bytes = await picked.readAsBytes();
    await _load(_bytes);
  }

  Size? get _imageSize {
    final image = _image;
    if (image == null) return null;
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  void _apply({Offset delta = Offset.zero, double scale = 1, Offset? anchor}) {
    final size = _imageSize;
    if (size == null) return;
    setState(() {
      _focal = focalAfterGesture(
        focal: _focal,
        box: const Size(_side, _side),
        image: size,
        delta: delta,
        scaleFactor: scale,
        anchor: anchor,
      );
    });
  }

  Future<void> _confirm() async {
    final image = _image;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    final png = await cropIconToPng(source: image, focal: _focal);
    if (mounted) Navigator.of(context).pop(png);
  }

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    return AlertDialog(
      title: const Text('アイコンの範囲を選ぶ'),
      content: SizedBox(
        width: _side,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _side,
              height: _side,
              child: size == null
                  ? const Center(child: CircularProgressIndicator())
                  : Listener(
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          _apply(scale: math.exp(-event.scrollDelta.dy / 500));
                        }
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: (d) {
                          _lastScale = 1;
                          _lastPoint = d.localFocalPoint;
                        },
                        onScaleUpdate: (d) {
                          final factor = d.scale / _lastScale;
                          _lastScale = d.scale;
                          final delta = d.localFocalPoint - _lastPoint;
                          _lastPoint = d.localFocalPoint;
                          _apply(
                            delta: delta,
                            scale: factor,
                            anchor:
                                d.localFocalPoint -
                                const Offset(_side / 2, _side / 2),
                          );
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRect(
                              child: CustomPaint(
                                painter: _CropPainter(_image!, _focal),
                              ),
                            ),
                            // 円の外側を暗くして、アイコンに使われる範囲を示す。
                            IgnorePointer(
                              child: CustomPaint(painter: _CircleMaskPainter()),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              'ドラッグで位置、ピンチ（PCはホイール）で大きさを変えられます',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _changeImage,
          child: const Text('画像を変更'),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: size == null || _saving ? null : _confirm,
          child: const Text('決定'),
        ),
      ],
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.focal);

  final ui.Image image;
  final ImageFocal focal;

  @override
  void paint(Canvas canvas, Size size) {
    final dest = iconCropDestRect(
      image: Size(image.width.toDouble(), image.height.toDouble()),
      focal: focal,
      size: size.width,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dest,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.focal != focal;
}

class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Offset.zero & size);
    canvas.drawPath(path, Paint()..color = Colors.black54);
    canvas.drawOval(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white70,
    );
  }

  @override
  bool shouldRepaint(_CircleMaskPainter old) => false;
}
