import 'dart:math';

import 'bgm_track.dart';

/// 再生の順序（2026-11-15）。順番は、最後の曲の次は先頭へ戻る（これまでの動き）。
enum BgmPlayOrder { inOrder, shuffle, repeatOne }

/// 曲が終わった時に、次に流す曲。[queue]は今のアルバム（または全曲）を再生順に並べたもの。
/// [current]が[queue]に無ければ先頭。曲が1つだけなら、どの順序でもその曲を繰り返す。
BgmTrack? nextBgmTrack({
  required List<BgmTrack> queue,
  required BgmTrack current,
  required BgmPlayOrder order,
  Random? random,
}) {
  if (queue.isEmpty) return null;
  if (order == BgmPlayOrder.repeatOne || queue.length == 1) {
    return queue.any((t) => t.id == current.id) ? current : queue.first;
  }
  final index = queue.indexWhere((t) => t.id == current.id);
  if (order == BgmPlayOrder.shuffle) {
    final others = [
      for (final t in queue)
        if (t.id != current.id) t,
    ];
    return others[(random ?? Random()).nextInt(others.length)];
  }
  return queue[(index + 1) % queue.length];
}

/// 一覧に出す並び（並び順→追加順）。
List<BgmTrack> sortBgmTracks(Iterable<BgmTrack> tracks) {
  final list = [...tracks];
  list.sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
  });
  return list;
}

/// 「次へ」「前へ」ボタンで進める曲（2026-11-15）。1曲リピートでも、ボタンでは一覧の隣へ進む。
/// シャッフルの「次へ」は、今の曲以外からの無作為。「前へ」はシャッフルでも一覧の前の曲。
BgmTrack? adjacentBgmTrack({
  required List<BgmTrack> queue,
  required BgmTrack current,
  required bool forward,
  required BgmPlayOrder order,
  Random? random,
}) {
  if (queue.isEmpty) return null;
  if (queue.length == 1) return queue.first;
  final index = queue.indexWhere((t) => t.id == current.id);
  if (forward) {
    if (order == BgmPlayOrder.shuffle) {
      final others = [
        for (final t in queue)
          if (t.id != current.id) t,
      ];
      return others[(random ?? Random()).nextInt(others.length)];
    }
    return queue[(index + 1) % queue.length];
  }
  return queue[(index - 1 + queue.length) % queue.length];
}
