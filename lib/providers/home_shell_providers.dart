import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `HomeScreen`の語らい/身だしなみ/設定タブのうち、どれが選択中かの
/// タブindex（2026-08-19追加）。`HomeScreen`自身の`_selectedIndex`
/// （`IndexedStack`用、常時3タブともマウントされたまま）を外部から
/// 参照するためのミラー。通話のピン留めミニ表示（`PinnedCallOverlay`）が
/// 「今、語らいタブを見ているか」を判定するのに使う。
class HomeSelectedTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int index) => state = index;
}

final homeSelectedTabProvider = NotifierProvider<HomeSelectedTabNotifier, int>(
  HomeSelectedTabNotifier.new,
);

/// `HomeScreen`のタブ順序における語らいタブのindex。
const kTalksTabIndex = 0;
