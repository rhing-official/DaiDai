import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';

/// ドローノートの1本の線（`notes/{noteId}/strokes/{strokeId}`、2026-10-04追加）。
///
/// 本文`content`ではなく1線1ドキュメントで保存することで、複数人が同時に
/// 描いても互いの線が上書きされない。座標は論理キャンバス（幅
/// [NoteStroke.canvasWidth]）上の値。
class NoteStroke {
  const NoteStroke({
    required this.strokeId,
    required this.points,
    required this.color,
    required this.width,
    required this.authorId,
    this.createdAt,
  });

  /// 論理キャンバスの幅。画面幅に合わせて拡縮して表示する。
  static const double canvasWidth = 1000;

  final String strokeId;

  /// x,y,x,y,...の平坦な座標列（小数1桁に丸め済み）。
  final List<double> points;

  /// 0xAARRGGBB。
  final int color;
  final double width;
  final String authorId;
  final Timestamp? createdAt;

  int get pointCount => points.length ~/ 2;

  Offset pointAt(int index) => Offset(points[index * 2], points[index * 2 + 1]);

  /// 線の外接矩形（太さ分の余白込み）。
  Rect get bounds {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < pointCount; i++) {
      final p = pointAt(i);
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    if (pointCount == 0) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(width / 2);
  }

  /// [position]（論理座標）が、太さ[tolerance]を加味してこの線に触れているか
  /// （消しゴム判定用）。
  bool hitTest(Offset position, double tolerance) {
    final reach = tolerance + width / 2;
    if (pointCount == 1) return (pointAt(0) - position).distance <= reach;
    for (var i = 0; i < pointCount - 1; i++) {
      if (_distanceToSegment(position, pointAt(i), pointAt(i + 1)) <= reach) {
        return true;
      }
    }
    return false;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSquared)
        .clamp(0.0, 1.0);
    return (p - Offset(a.dx + ab.dx * t, a.dy + ab.dy * t)).distance;
  }

  factory NoteStroke.fromJson(String strokeId, Map<String, dynamic> json) {
    return NoteStroke(
      strokeId: strokeId,
      points: [
        for (final v in (json['points'] as List? ?? const []))
          (v as num).toDouble(),
      ],
      color: (json['color'] as num?)?.toInt() ?? 0xFF000000,
      width: (json['width'] as num?)?.toDouble() ?? 4,
      authorId: json['authorId'] as String? ?? '',
      createdAt: json['createdAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {
    'points': points,
    'color': color,
    'width': width,
    'authorId': authorId,
    'createdAt': createdAt ?? FieldValue.serverTimestamp(),
  };
}
