import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/strings.dart';

import 'app_dialog.dart';

/// ハニカム（丸が六角形に並んだ）色選びの1マス（2026-11-14）。[q]・[r]は六角配置の軸座標
/// （中心が0,0）、[color]はそのマスの色。グレーの行は[gray]がtrue（座標は行の位置）。
class HoneycombCell {
  const HoneycombCell({
    required this.q,
    required this.r,
    required this.color,
    this.gray = false,
  });

  final int q;
  final int r;
  final Color color;
  final bool gray;
}

/// 六角形の外側のリング数（中心＋この数のリングで127マス）。
const kHoneycombRings = 6;

/// 色のマス一覧。中央が白で、外側へ色相が一周し、リング0〜3は白から色へ（彩度）、
/// リング4〜6は濃くなる（明度）。最後にグレー（白→黒）7マスの行を足す。
List<HoneycombCell> honeycombCells() {
  final cells = <HoneycombCell>[];
  for (var r = -kHoneycombRings; r <= kHoneycombRings; r++) {
    for (var q = -kHoneycombRings; q <= kHoneycombRings; q++) {
      final s = -q - r;
      final ring = math.max(q.abs(), math.max(r.abs(), s.abs()));
      if (ring > kHoneycombRings) continue;
      if (ring == 0) {
        cells.add(HoneycombCell(q: q, r: r, color: Colors.white));
        continue;
      }
      final x = q + r / 2;
      final y = r * math.sqrt(3) / 2;
      var hue = math.atan2(y, x) * 180 / math.pi;
      if (hue < 0) hue += 360;
      final saturation = ring <= 3 ? ring / 3 : 1.0;
      final value = ring <= 3 ? 1.0 : 1 - (ring - 3) / 4;
      cells.add(
        HoneycombCell(
          q: q,
          r: r,
          color: HSVColor.fromAHSV(1, hue, saturation, value).toColor(),
        ),
      );
    }
  }
  const grayCount = 7;
  for (var i = 0; i < grayCount; i++) {
    final v = 1 - i / (grayCount - 1);
    cells.add(
      HoneycombCell(
        q: i - grayCount ~/ 2,
        r: kHoneycombRings + 2,
        color: HSVColor.fromAHSV(1, 0, 0, v).toColor(),
        gray: true,
      ),
    );
  }
  return cells;
}

double _distance(Color a, Color b) {
  final dr = (a.r - b.r) * 255;
  final dg = (a.g - b.g) * 255;
  final db = (a.b - b.b) * 255;
  return dr * dr + dg * dg + db * db;
}

/// 丸の六角配置の色選び。マスをタップすると[onPicked]を呼ぶ。[current]に一番近いマスに
/// 枠を付ける。
class HoneycombColorPicker extends StatelessWidget {
  const HoneycombColorPicker({
    required this.onPicked,
    this.current,
    this.diameter = 24,
    super.key,
  });

  final ValueChanged<Color> onPicked;
  final Color? current;

  /// 1マスの間隔（丸の直径は少し小さい）。
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final cells = honeycombCells();
    final rowHeight = diameter * math.sqrt(3) / 2;
    final width = diameter * (kHoneycombRings * 2 + 1);
    final height = rowHeight * (kHoneycombRings * 2 + 2) + diameter;
    final cur = current;
    HoneycombCell? nearest;
    if (cur != null) {
      var best = double.infinity;
      for (final cell in cells) {
        final d = _distance(cell.color, cur);
        if (d < best) {
          best = d;
          nearest = cell;
        }
      }
    }
    final outline = Theme.of(context).colorScheme.onSurface;
    final dot = diameter - 3;
    Offset centerOf(HoneycombCell cell) => Offset(
      width / 2 + (cell.gray ? cell.q : cell.q + cell.r / 2) * diameter,
      (cell.r + kHoneycombRings) * rowHeight +
          (cell.gray ? rowHeight * 0.4 : 0) +
          diameter / 2,
    );
    // 押したまま滑らせて選べる（指・ポインタが乗っている丸を、動くたびに選ぶ）。
    void pickAt(Offset position) {
      HoneycombCell? hit;
      var best = diameter * diameter / 4;
      for (final cell in cells) {
        final d = (centerOf(cell) - position).distanceSquared;
        if (d <= best) {
          best = d;
          hit = cell;
        }
      }
      if (hit != null) onPicked(hit.color);
    }

    return SizedBox(
      width: width,
      height: height + rowHeight,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => pickAt(e.localPosition),
        onPointerMove: (e) => pickAt(e.localPosition),
        child: Stack(
          children: [
            for (final cell in cells)
              Positioned(
                left:
                    width / 2 +
                    (cell.gray ? cell.q : cell.q + cell.r / 2) * diameter -
                    dot / 2,
                top:
                    (cell.r + kHoneycombRings) * rowHeight +
                    (cell.gray ? rowHeight * 0.4 : 0) +
                    (diameter - dot) / 2,
                child: IgnorePointer(
                  key: ValueKey('honeycomb-${cell.q}-${cell.r}'),
                  child: Container(
                    width: dot,
                    height: dot,
                    decoration: BoxDecoration(
                      color: cell.color,
                      shape: BoxShape.circle,
                      border: identical(cell, nearest)
                          ? Border.all(color: outline, width: 2.5)
                          : Border.all(color: Colors.black12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ハニカムの色選びをポップアップ（画面遷移の設定に従う）で開く。丸をタップしても閉じず、
/// 選んだ色を見本に出すだけで、[doneLabel]のボタンで確定してその色を返す。外側のタップ・
/// 戻る操作は`null`（変更なし）。反映の処理を最後の1回に絞る為、試す間は何も反映しない
/// （2026-11-14）。
Future<Color?> showHoneycombColorDialog(
  BuildContext context, {
  Color? current,
  String doneLabel = 'OK',
}) {
  return showAppDialog<Color>(
    context: context,
    builder: (dialogContext) =>
        _HoneycombDialog(current: current, doneLabel: doneLabel),
  );
}

class _HoneycombDialog extends StatefulWidget {
  const _HoneycombDialog({required this.current, required this.doneLabel});

  final Color? current;
  final String doneLabel;

  @override
  State<_HoneycombDialog> createState() => _HoneycombDialogState();
}

class _HoneycombDialogState extends State<_HoneycombDialog> {
  late Color? _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AlertDialog(
      contentPadding: const EdgeInsets.all(20),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HoneycombColorPicker(
            current: selected,
            onPicked: (color) => setState(() => _selected = color),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black26),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                selected == null
                    ? ''
                    : '#${selected.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                style: TextStyle(color: onSurface),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.of(context).pop(selected),
              child: Text(widget.doneLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// 色の入力欄の右端に置く、ハニカムの色選びを開くボタン。選ばれた色を[onPicked]へ渡す
/// （アルファを持つ欄は、受け取り側で元のアルファを保つ）。
class HoneycombColorButton extends ConsumerWidget {
  const HoneycombColorButton({required this.onPicked, this.current, super.key});

  final ValueChanged<Color> onPicked;
  final Color? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doneLabel = ref.watch(appStringsProvider).workshopFocalDone;
    return IconButton(
      icon: const Icon(Icons.hexagon_outlined),
      tooltip: '',
      onPressed: () async {
        final picked = await showHoneycombColorDialog(
          context,
          current: current,
          doneLabel: doneLabel,
        );
        if (picked != null) onPicked(picked);
      },
    );
  }
}
