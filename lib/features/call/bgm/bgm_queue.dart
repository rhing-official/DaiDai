import 'dart:math';

import 'bgm_track.dart';

/// 再生の順序（2026-11-15）。順番は、最後の曲の次は先頭へ戻る（これまでの動き）。
/// [inOrderNextAlbum]（2026-11-16）は、アルバムの最後の曲が終わったら、次のアルバムの先頭へ進む
/// （アルバムの中から流した時だけ。全曲・お気に入りでは[inOrder]と同じ）。
/// 設定には名前で保存する為、並びを変えても保存済みの値は壊れない。
enum BgmPlayOrder { inOrder, inOrderNextAlbum, shuffle, repeatOne }

/// 再生の範囲として「アルバムに入っていない曲」を表す印（アルバムのidとしては使えない値）。
/// アーティストの一覧の「アルバムなし」から流した時に使う。
const kBgmUnclassifiedScope = '__unclassified__';

/// アルバムの最後の曲の次に流す、次のアルバムの先頭の曲（[BgmPlayOrder.inOrderNextAlbum]用、2026-11-16）。
/// [scopes]はアルバムを回る順（最後に[kBgmUnclassifiedScope]）、[currentScope]が今のアルバム。
/// 曲が無いアルバムは飛ばし、最後の次は最初へ戻る。今のアルバム以外に曲のあるアルバムが無ければnull
/// （呼び出し側は、今のアルバムの先頭へ戻る）。
({String scope, BgmTrack track})? firstTrackOfNextAlbum({
  required List<String> scopes,
  required String currentScope,
  required List<BgmTrack> Function(String scope) tracksOf,
}) {
  final start = scopes.indexOf(currentScope);
  for (var step = 1; step < scopes.length; step++) {
    final scope = scopes[(start + step) % scopes.length];
    if (scope == currentScope) continue;
    final tracks = tracksOf(scope);
    if (tracks.isNotEmpty) return (scope: scope, track: tracks.first);
  }
  return null;
}

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
