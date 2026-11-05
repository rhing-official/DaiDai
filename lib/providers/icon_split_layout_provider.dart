import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_shell_providers.dart';

const _railKey = 'iconSplitRailFraction';
const _listKey = 'iconSplitListFraction';
const _computerListKey = 'computerTalksListWidth';

/// 「アイコン＋寄合一覧」の、区切り線をドラッグして決めた幅（画面の幅に対する割合、
/// 2026-11-05）。nullは未設定＝標準の幅（「一覧の大きさ」に連動）。端末ごとの保存のみ。
class IconSplitLayout {
  const IconSplitLayout({
    this.railFraction,
    this.listFraction,
    this.computerListWidth,
  });

  /// アイコン列の幅の割合。
  final double? railFraction;

  /// 寄合一覧（メッセージ画面の隣に出す広い画面のみ）の幅の割合。
  final double? listFraction;

  /// コンピューターの左右分割で、語らい一覧の幅（px、標準は260）。
  final double? computerListWidth;

  IconSplitLayout copyWith({
    double? railFraction,
    double? listFraction,
    bool clearRail = false,
    double? computerListWidth,
    bool clearList = false,
    bool clearComputerList = false,
  }) => IconSplitLayout(
    railFraction: clearRail ? null : (railFraction ?? this.railFraction),
    listFraction: clearList ? null : (listFraction ?? this.listFraction),
    computerListWidth: clearComputerList
        ? null
        : (computerListWidth ?? this.computerListWidth),
  );
}

final initialIconSplitLayoutProvider = Provider<IconSplitLayout>(
  (ref) => const IconSplitLayout(),
);

Future<IconSplitLayout> loadInitialIconSplitLayout() async {
  final prefs = await SharedPreferences.getInstance();
  return IconSplitLayout(
    railFraction: prefs.getDouble(_railKey),
    listFraction: prefs.getDouble(_listKey),
    computerListWidth: prefs.getDouble(_computerListKey),
  );
}

class IconSplitLayoutNotifier extends Notifier<IconSplitLayout> {
  @override
  IconSplitLayout build() => ref.watch(initialIconSplitLayoutProvider);

  /// ドラッグ中は保存せず状態だけ更新する（[persist]で保存）。
  void setRail(double fraction) =>
      state = state.copyWith(railFraction: fraction);
  void setList(double fraction) =>
      state = state.copyWith(listFraction: fraction);

  void setComputerList(double width) =>
      state = state.copyWith(computerListWidth: width);

  void resetComputerList() {
    state = state.copyWith(clearComputerList: true);
    persist();
  }

  /// 標準の幅に戻す。
  void resetRail() {
    state = state.copyWith(clearRail: true);
    persist();
  }

  void resetList() {
    state = state.copyWith(clearList: true);
    persist();
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    final rail = state.railFraction;
    final list = state.listFraction;
    if (rail == null) {
      await prefs.remove(_railKey);
    } else {
      await prefs.setDouble(_railKey, rail);
    }
    if (list == null) {
      await prefs.remove(_listKey);
    } else {
      await prefs.setDouble(_listKey, list);
    }
    final computerList = state.computerListWidth;
    if (computerList == null) {
      await prefs.remove(_computerListKey);
    } else {
      await prefs.setDouble(_computerListKey, computerList);
    }
  }
}

final iconSplitLayoutProvider =
    NotifierProvider<IconSplitLayoutNotifier, IconSplitLayout>(
      IconSplitLayoutNotifier.new,
    );

/// 区切り線の幅調整モード（2026-11-05）。普段はオフで、区切り線はドラッグもダブルタップも
/// 効かない（指が触れただけで幅が動くのを防ぐ）。設定の「幅を調整する」で入り、
/// 語らいタブ以外へ移ると自動で終わる。保存しない。
class IconSplitAdjustingNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.listen<int>(homeSelectedTabProvider, (_, next) {
      if (next != kTalksTabIndex && state) state = false;
    });
    return false;
  }

  void set(bool value) => state = value;
}

final iconSplitAdjustingProvider =
    NotifierProvider<IconSplitAdjustingNotifier, bool>(
      IconSplitAdjustingNotifier.new,
    );

/// 区切り線をドラッグしている最中の、アイコン列・寄合一覧の幅（px、2026-11-05）。
/// 語らいタブ全体を作り直さず、幅を決める小さな部品だけを更新して指に追従させるための
/// 一時値。指を離したら[iconSplitLayoutProvider]へ確定してnullに戻す。
class IconSplitDragNotifier extends Notifier<({double rail, double list})?> {
  @override
  ({double rail, double list})? build() => null;

  void set(({double rail, double list}) value) => state = value;
  void clear() => state = null;
}

final iconSplitDragProvider =
    NotifierProvider<IconSplitDragNotifier, ({double rail, double list})?>(
      IconSplitDragNotifier.new,
    );
