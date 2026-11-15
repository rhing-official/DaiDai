import 'package:flutter_riverpod/flutter_riverpod.dart';

/// PC・Webの通話画面で、拡大している（通話エリアいっぱいに広げた）タイルのキー（2026-11-15）。
/// nullならグリッド。広場は参加者の`userId`と`<userId>#screen`、1対1は`remote`・`self`・
/// `screen-remote`・`screen-self`。通話画面の外の余白のクリックが、ミニ表示にする前に、
/// まず拡大を解除できるよう、ステージの外から読み書きできる所に置く。`autoDispose`なので、
/// 通話画面を閉じる・通話が終わると拡大は解除される。
class CallFocusedTileNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void focus(String key) => state = key;

  void clear() => state = null;
}

final callFocusedTileProvider =
    NotifierProvider.autoDispose<CallFocusedTileNotifier, String?>(
      CallFocusedTileNotifier.new,
    );
