import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 通話ミニ表示（`PinnedCallOverlay`）の大きさ。
const kPinnedCallSize = Size(140, 200);

/// 画面の端との既定の余白。
const kPinnedCallMargin = 8.0;

/// ドラッグで動かしたミニ表示の左上の位置（2026-10-11追加）。nullは既定の
/// 右上。通話が終わるとリセットされ、永続保存はしない。
class PinnedCallOffsetNotifier extends Notifier<Offset?> {
  @override
  Offset? build() => null;

  void set(Offset? value) => state = value;
}

final pinnedCallOffsetProvider =
    NotifierProvider<PinnedCallOffsetNotifier, Offset?>(
      PinnedCallOffsetNotifier.new,
    );

/// ミニ表示の左上[offset]（nullは既定の右上）を、画面[screen]の中（上は
/// [topInset]＝ステータスバー等の分を避ける）に収まるよう補正した位置。
Offset clampPinnedCallOffset({
  required Offset? offset,
  required Size screen,
  required double topInset,
  Size bubble = kPinnedCallSize,
}) {
  final minX = 0.0;
  final minY = topInset;
  final maxX = math.max(minX, screen.width - bubble.width);
  final maxY = math.max(minY, screen.height - bubble.height);
  final base =
      offset ??
      Offset(
        screen.width - bubble.width - kPinnedCallMargin,
        topInset + kPinnedCallMargin,
      );
  return Offset(base.dx.clamp(minX, maxX), base.dy.clamp(minY, maxY));
}

/// ポインター位置に完全に追従させる、ドラッグ中のミニ表示の左上の位置
/// （2026-10-13）。[grab]はドラッグ開始時の「ポインター位置 − ミニ表示の左上」。
/// 前回位置への加算（相対移動）ではなく毎回ポインターの絶対位置から求めるため、
/// 再描画前に複数のイベントが届いても移動量を取りこぼさない。
Offset pinnedCallOffsetForPointer({
  required Offset pointer,
  required Offset grab,
  required Size screen,
  required double topInset,
  Size bubble = kPinnedCallSize,
}) {
  return clampPinnedCallOffset(
    offset: pointer - grab,
    screen: screen,
    topInset: topInset,
    bubble: bubble,
  );
}
