import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 下端に横並びのメニューチップの帯が、画面上（global座標）で占める範囲（2026-11-29）。
/// チップの下へ潜り込む部品（アイコン+寄合一覧のアイコン列、`NavChipHalo`）が、チップの周りを
/// 滲ませる為に読む。チップが縦並び（広い画面）の時、又はまだ描かれていない時はnull。
class NavChipBandRectNotifier extends Notifier<Rect?> {
  @override
  Rect? build() => null;

  void set(Rect? rect) {
    if (state == rect) return;
    state = rect;
  }
}

final navChipBandRectProvider =
    NotifierProvider<NavChipBandRectNotifier, Rect?>(
      NavChipBandRectNotifier.new,
    );
