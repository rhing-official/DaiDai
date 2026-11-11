/// 縦表示（狭い画面）の下部メニューチップの揃え（2026-11-01）。標準は中央。
enum NavChipAlignment {
  start,
  center,
  end;

  static NavChipAlignment fromName(String? name) {
    return NavChipAlignment.values.firstWhere(
      (alignment) => alignment.name == name,
      orElse: () => NavChipAlignment.center,
    );
  }
}

/// ホームのタブ。enumの宣言順（`index`）がホーム画面の論理インデックス
/// （`IndexedStack`・`homeSelectedTabProvider`・戻る履歴のスコープが前提にする値）で、
/// チップの表示順を入れ替えても変わらない。
enum HomeTabId {
  talk,
  profile,
  settings,

  /// 保存したアカウントが2つ以上の時だけ出る、アカウント切り替えのタブ（2026-11-11）。
  account;

  static HomeTabId? tryParse(String? name) {
    for (final tab in HomeTabId.values) {
      if (tab.name == name) return tab;
    }
    return null;
  }
}

/// 保存された並び[names]を、常に全タブ（[HomeTabId.values]）を1回ずつ含む並びに直す。不明な名前・重複は
/// 捨て、足りないタブは標準の順で末尾へ補う（別の版で保存された値でも壊れないように）。
List<HomeTabId> normalizeNavChipOrder(Iterable<String>? names) {
  final order = <HomeTabId>[];
  for (final name in names ?? const <String>[]) {
    final tab = HomeTabId.tryParse(name);
    if (tab != null && !order.contains(tab)) order.add(tab);
  }
  for (final tab in HomeTabId.values) {
    if (!order.contains(tab)) order.add(tab);
  }
  return order;
}

/// 下部メニューチップの揃えと並び。
class NavChipLayout {
  const NavChipLayout({
    this.alignment = NavChipAlignment.center,
    this.wideAlignment = NavChipAlignment.center,
    this.order = const [
      HomeTabId.talk,
      HomeTabId.profile,
      HomeTabId.settings,
      HomeTabId.account,
    ],
  });

  static const standard = NavChipLayout();

  /// 縦表示（狭い画面、下端の横並び）の揃え。左・中央・右。
  final NavChipAlignment alignment;

  /// 横表示（広い画面、左端の縦並び）の揃え。上・中央・下（2026-11-06、以前は[alignment]と
  /// 共通で「上揃え＝左揃え」として扱っていたのを、別々に保存するように分けた）。
  final NavChipAlignment wideAlignment;

  /// チップを左から並べるタブの順。
  final List<HomeTabId> order;

  NavChipLayout copyWith({
    NavChipAlignment? alignment,
    NavChipAlignment? wideAlignment,
    List<HomeTabId>? order,
  }) => NavChipLayout(
    alignment: alignment ?? this.alignment,
    wideAlignment: wideAlignment ?? this.wideAlignment,
    order: order ?? this.order,
  );
}

/// 画面に出すチップの並び（論理インデックス）。[showAccount]が偽なら、保存済みの並びに
/// 含まれていても[HomeTabId.account]は出さない（2026-11-11）。
List<int> visibleNavChipIndexes(
  Iterable<HomeTabId> order, {
  required bool showAccount,
}) => [
  for (final tab in order)
    if (tab != HomeTabId.account || showAccount) tab.index,
];
