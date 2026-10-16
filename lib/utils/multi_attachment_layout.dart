import 'dart:math' as math;
import 'dart:ui';

/// 複数添付（`contentType: 'multi'`）のメディアグリッドの配置結果
/// （2026-10-16追加）。
class MultiAttachmentLayout {
  const MultiAttachmentLayout({required this.height, required this.tiles});

  /// 全体の高さ（幅は呼び出し側が渡した`width`）。
  final double height;

  /// 各メディアの矩形（入力と同じ順序、原点は左上）。
  final List<Rect> tiles;
}

/// [count]枚のメディアを、全体がきれいな正方形か長方形になるよう並べる。
/// 枚数ごとの構成: 2=左右2枚、3=左に大1枚＋右に2枚を縦積み、4=2×2、
/// 6=3×2、8=4×2、9=3×3。5・7・10は1枚目を全幅（2:1）に拡大し、下段に
/// 4列・3列×2行・3列×3行で並べる。1枚（ファイル混在の時）は縦3:4。
/// 11枚以上（送信側の上限は10）は10枚と同じ形で、最後の行が欠ける。
MultiAttachmentLayout multiAttachmentLayout(
  int count,
  double width, {
  double gap = 2,
}) {
  if (count <= 0) return const MultiAttachmentLayout(height: 0, tiles: []);

  List<Rect> grid(int columns, int rows, double top, {int? limit}) {
    final cell = (width - gap * (columns - 1)) / columns;
    final tiles = <Rect>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        if (limit != null && tiles.length >= limit) return tiles;
        tiles.add(
          Rect.fromLTWH(c * (cell + gap), top + r * (cell + gap), cell, cell),
        );
      }
    }
    return tiles;
  }

  final List<Rect> tiles;
  switch (count) {
    case 1:
      tiles = [Rect.fromLTWH(0, 0, width, width * 0.75)];
    case 2:
      tiles = grid(2, 1, 0);
    case 3:
      final cell = (width - gap * 2) / 3;
      final big = cell * 2 + gap;
      tiles = [
        Rect.fromLTWH(0, 0, big, big),
        Rect.fromLTWH(big + gap, 0, cell, cell),
        Rect.fromLTWH(big + gap, cell + gap, cell, cell),
      ];
    case 4:
      tiles = grid(2, 2, 0);
    case 6:
      tiles = grid(3, 2, 0);
    case 8:
      tiles = grid(4, 2, 0);
    case 9:
      tiles = grid(3, 3, 0);
    case 5:
      tiles = [
        Rect.fromLTWH(0, 0, width, width / 2),
        ...grid(4, 1, width / 2 + gap),
      ];
    case 7:
      tiles = [
        Rect.fromLTWH(0, 0, width, width / 2),
        ...grid(3, 2, width / 2 + gap),
      ];
    default:
      // 10枚（11枚以上は最後の行が欠ける）。
      final rest = count - 1;
      tiles = [
        Rect.fromLTWH(0, 0, width, width / 2),
        ...grid(3, (rest / 3).ceil(), width / 2 + gap, limit: rest),
      ];
  }
  final height = tiles.fold<double>(0, (h, r) => math.max(h, r.bottom));
  return MultiAttachmentLayout(height: height, tiles: tiles);
}
