/// アプリの文字に使うフォント（2026-09-06追加）。端末ごとの個人設定で、
/// フラット・劇画・ガラス全てのUIスタイルの`TextTheme`に適用する
/// （劇画は見出し・ロゴ・カウンター表示のみ固定のAntonを上書き適用する、
/// `GekigaTheme`参照）。
enum FontDesign {
  /// プラットフォーム既定のフォントのまま変更しない。
  standard,

  /// はんなり明朝（IPAフォントライセンスv1.0、IPAex明朝の派生）。
  hannariMincho,

  /// KHドットフォント 12神楽坂（SIL Open Font License 1.1）。ドット
  /// （ビットマップ風）の明朝体。
  kagurazaka,

  /// キウイ丸（SIL Open Font License 1.1）。企画書の極みプラン限定
  /// 「追加フォント10種」の1つ（2026-09-06追加、[isKiwamiExclusive]参照）。
  kiwiMaru,

  /// しっぽり明朝（SIL Open Font License 1.1）。企画書の極みプラン限定
  /// 「追加フォント10種」の1つ（2026-09-06追加、[isKiwamiExclusive]参照）。
  shipporiMincho;

  /// pubspec.yamlに登録したfontFamily名。[standard]はnull
  /// （`TextTheme.apply`にnullを渡すとフォントを変更しない）。
  String? get fontFamily => switch (this) {
    FontDesign.standard => null,
    FontDesign.hannariMincho => 'HannariMincho',
    FontDesign.kagurazaka => 'KHDotKagurazaka16',
    FontDesign.kiwiMaru => 'KiwiMaru',
    FontDesign.shipporiMincho => 'ShipporiMincho',
  };

  /// 企画書6章「有料プラン『極み』」の「追加フォント10種」に該当するか
  /// （2026-09-06追加）。現時点では極みプラン自体の課金判定ロジックが
  /// 未実装のため、この値は表示上の目印（設定画面のバッジ等）にのみ使い、
  /// 選択自体は誰でも行える。極みプラン本体を実装する際に、ここを見て
  /// 選択を制限する形に変更する想定。
  bool get isKiwamiExclusive => switch (this) {
    FontDesign.kiwiMaru => true,
    FontDesign.shipporiMincho => true,
    FontDesign.standard => false,
    FontDesign.hannariMincho => false,
    FontDesign.kagurazaka => false,
  };

  static FontDesign fromName(String? name) {
    return FontDesign.values.firstWhere(
      (design) => design.name == name,
      orElse: () => FontDesign.standard,
    );
  }
}
