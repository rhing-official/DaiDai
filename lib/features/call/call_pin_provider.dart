import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'active_call_session.dart';

/// 通話画面で、ピン留めしたウィンドウのキーの集合（2026-11-16）。キーは、広場は参加者の
/// `userId`と`<userId>#screen`、一対は`self`・`remote`・`self#screen`・`remote#screen`。
/// ピンしたウィンドウは大きく、残りは下の細い帯に並ぶ（`CallTileStage`）。通話画面の外の
/// 余白のクリックが、ミニ表示にする前に、まずピンを外せるよう、ステージの外から読み書きできる
/// 所に置く。ミニ表示にして通話画面を閉じても、戻した時にピンは残る（2026-11-17、以前は
/// `autoDispose`で外れていた）。通話が終わる・別の通話に変わると外れる。
class CallPinnedTilesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(activeCallSessionProvider.select((s) => s?.controllerListenable));
    return const {};
  }

  void toggle(String key) {
    final next = {...state};
    if (!next.remove(key)) next.add(key);
    state = next;
  }

  void clear() {
    if (state.isNotEmpty) state = const {};
  }

  /// [valid]に無いキー（共有の終了・退出で無くなったウィンドウ）のピンを外す。
  void retain(Set<String> valid) {
    final next = state.where(valid.contains).toSet();
    if (next.length != state.length) state = next;
  }
}

final callPinnedTilesProvider =
    NotifierProvider<CallPinnedTilesNotifier, Set<String>>(
      CallPinnedTilesNotifier.new,
    );
