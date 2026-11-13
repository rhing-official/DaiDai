import 'dart:ui' show Offset;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `HomeScreen`の語らい/身だしなみ/設定タブのうち、どれが選択中かの
/// タブindex（2026-08-19追加）。`HomeScreen`自身の`_selectedIndex`
/// （`IndexedStack`用、常時3タブともマウントされたまま）を外部から
/// 参照する為のミラー。通話のピン留めミニ表示（`PinnedCallOverlay`）が
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

/// 次のタブ切り替えを、横スライドではなくダイアログと同じ「現れ方」（設定>画面遷移の
/// 種類）で見せる依頼（2026-11-06）。プロフィールカードの「身だしなみへ」のように、
/// ダイアログが閉じる流れで別のタブへ飛ぶ時に使う。`HomeScreen`が切り替えを受けた時に
/// 読み取って降ろす（1回限り）。
class HomeTabAppearRequestNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;

  /// 立てられていたらtrueを返して降ろす。
  bool consume() {
    final requested = state;
    if (requested) state = false;
    return requested;
  }
}

final homeTabAppearRequestProvider =
    NotifierProvider<HomeTabAppearRequestNotifier, bool>(
      HomeTabAppearRequestNotifier.new,
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

/// メニューチップから始めたタッチを、そのまま項目一覧（設定・身だしなみのトップ）へ
/// 滑らせて選べるようにする橋渡し（2026-11-03）。項目一覧（`SlideSelectList`）が表示中
/// だけ自分を登録し、`HomeScreen`のチップ列は、指がチップ列の外へ出たら[active]の
/// 項目へ選択を渡す。
abstract class ItemPickTarget {
  /// 今、項目一覧が見えていて、他の層に覆われていないか。
  bool isActiveAt(Offset globalPosition);

  /// [globalPosition]の下にある項目の番号。項目一覧の外ならnull。
  int? indexAt(Offset globalPosition);

  /// 項目を選ぶ。[commit]がfalseの間は選択中の強調（広い画面ではその場の選択）、
  /// trueは指を離した確定（狭い画面では項目を開く）。[index]がnullなら強調を消す。
  void pick(int? index, {required bool commit});
}

class ItemPickBridge {
  final List<ItemPickTarget> _targets = [];

  /// 診断用（2026-11-12、滑らせて選ぶが効かない原因の切り分け）。
  int get debugTargetCount => _targets.length;

  void register(ItemPickTarget target) => _targets.add(target);
  void unregister(ItemPickTarget target) => _targets.remove(target);

  /// [globalPosition]に項目一覧がある登録先（無ければnull）。
  ItemPickTarget? targetAt(Offset globalPosition) {
    for (final target in _targets) {
      if (target.isActiveAt(globalPosition)) return target;
    }
    return null;
  }
}

final itemPickBridgeProvider = Provider<ItemPickBridge>(
  (ref) => ItemPickBridge(),
);
