import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 通話画面で、ピン留めしたウィンドウのキーの集合（2026-11-16）。キーは、広場は参加者の
/// `userId`と`<userId>#screen`、一対は`self`・`remote`・`self#screen`・`remote#screen`。
/// ピンしたウィンドウは大きく、残りは下の細い帯に並ぶ（`CallTileStage`）。通話画面の外の
/// 余白のクリックが、ミニ表示にする前に、まずピンを外せるよう、ステージの外から読み書きできる
/// 所に置く。`autoDispose`なので、通話画面を閉じる・通話が終わるとピンは外れる。
class CallPinnedTilesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

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
    NotifierProvider.autoDispose<CallPinnedTilesNotifier, Set<String>>(
      CallPinnedTilesNotifier.new,
    );
