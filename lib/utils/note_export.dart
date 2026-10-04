import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/painting.dart';

import '../models/note_stroke.dart';

/// 線[stroke]を[canvas]へ描く（キャンバス表示とPNG書き出しで共有）。
void paintNoteStroke(Canvas canvas, NoteStroke stroke) {
  final paint = Paint()
    ..color = Color(stroke.color)
    ..strokeWidth = stroke.width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  if (stroke.pointCount == 1) {
    canvas.drawCircle(
      stroke.pointAt(0),
      stroke.width / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  final path = Path()..moveTo(stroke.points[0], stroke.points[1]);
  for (var i = 1; i < stroke.pointCount; i++) {
    path.lineTo(stroke.points[i * 2], stroke.points[i * 2 + 1]);
  }
  canvas.drawPath(path, paint);
}

/// 全ての線を白背景・外接矩形＋余白でPNGにする。線が無ければnull。
Future<Uint8List?> renderStrokesToPng(
  List<NoteStroke> strokes, {
  double margin = 40,
  double pixelRatio = 2,
}) async {
  final drawable = strokes.where((s) => s.pointCount > 0).toList();
  if (drawable.isEmpty) return null;
  var bounds = drawable.first.bounds;
  for (final s in drawable.skip(1)) {
    bounds = bounds.expandToInclude(s.bounds);
  }
  bounds = bounds.inflate(margin);
  // 極端に大きな画像でメモリを使い切らないよう、一辺の上限を決めて縮小する。
  const maxSide = 8000.0;
  final ratio = [
    pixelRatio,
    maxSide / bounds.width,
    maxSide / bounds.height,
  ].reduce((a, b) => a < b ? a : b);
  final width = (bounds.width * ratio).ceil();
  final height = (bounds.height * ratio).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  canvas.scale(ratio);
  canvas.translate(-bounds.left, -bounds.top);
  for (final s in drawable) {
    paintNoteStroke(canvas, s);
  }
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// ファイル名に使えない文字を置換し、空なら[fallback]にする。
String sanitizeFileName(String name, String fallback) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  return cleaned.isEmpty ? fallback : cleaned;
}

/// 端末へ保存する（Web=ダウンロード、デスクトップ=保存ダイアログ、
/// モバイル=共有シート/保存先選択。`file_picker`の`saveFile`が各プラット
/// フォームを吸収する）。キャンセルされたらfalse。
Future<bool> saveNoteFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  final result = await FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: mimeType,
  );
  return result != null;
}
