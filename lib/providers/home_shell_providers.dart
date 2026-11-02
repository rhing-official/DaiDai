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

/// `HomeScreen`のタブ順序における身だしなみタブのindex。
const kProfileTabIndex = 1;

/// 身だしなみタブで「仕立て」を開く依頼（2026-10-31追加）。値を増やすたびに
/// `ProfileTab`が仕立てへ切り替える（メッセージ画面の自分のプロフィールカードから
/// 仕立てへ移動する時に使う）。
class OpenWorkshopRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state = state + 1;
}

final openWorkshopRequestProvider =
    NotifierProvider<OpenWorkshopRequestNotifier, int>(
      OpenWorkshopRequestNotifier.new,
    );

/// 設定・身だしなみのトップの横ドラッグ（`HomeTabSwipe`）を、`HomeScreen`のタブ
/// スライドへ指に追従して伝える橋渡し（2026-11-02）。`HomeScreen`が表示中だけ
/// コールバックを差す。
class HomeTabDragController {
  /// 指の横移動量（px、右が正）。
  void Function(double dx)? onDelta;

  /// 指を離した時の横方向の速さ（px/秒、右が正）。キャンセルは0。
  void Function(double velocity)? onEnd;
}

final homeTabDragControllerProvider = Provider<HomeTabDragController>(
  (ref) => HomeTabDragController(),
);
