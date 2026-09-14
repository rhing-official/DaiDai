/// アプリの文字に使うフォント（2026-09-06追加）。端末ごとの個人設定で、
/// フラット・劇画・ガラス全てのUIスタイルの`TextTheme`に適用する
/// （劇画は見出し・ロゴ・カウンター表示のみ固定のAntonを上書き適用する、
/// `GekigaTheme`参照）。
///
/// [standard]（プラットフォーム既定のフォントのまま変更しない選択肢）は
/// 2026-09-14にユーザー指示で廃止した。全ての選択肢が具体的なフォントを
/// 指定する（[fontFamily]が非null）。
enum FontDesign {
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
  shipporiMincho,

  /// Noto Sans JP（Google/Adobe、SIL Open Font License 1.1）。角ゴシック
  /// の定番。2026-09-14追加。
  notoSansJp,

  /// Noto Serif JP（Google/Adobe、SIL Open Font License 1.1）。明朝体の
  /// 定番。2026-09-14追加。
  notoSerifJp,

  /// 源真ゴシック（自家製フォント工房、SIL Open Font License 1.1）。
  /// 源ノ角ゴシック（Noto Sans CJK）ベースの角ゴシック。2026-09-14追加。
  genShinGothic,

  /// 源柔ゴシック（自家製フォント工房、SIL Open Font License 1.1）。
  /// 源真ゴシックの丸ゴシック版。2026-09-14追加。
  genJyuuGothic,

  /// 自家製 Rounded M+（自家製フォント工房、M+ FONT LICENSE）。やわらかい
  /// 丸ゴシック。2026-09-14追加。
  roundedMPlus,

  /// 851ゴチカクット（8:51:22 pm、非商用/商用利用とも許諾済みの独自利用規約）。
  /// カクカクした電機文字風のデザインフォント。2026-09-14追加。
  gochikakutto851,

  /// だるまドロップ（Maniackers Design、SIL Open Font License 1.1）。
  /// 和紙のような質感の手描き風ディスプレイフォント。2026-09-14追加。
  darumadropOne,

  /// Zen Kaku Gothic New（Zenlab、SIL Open Font License 1.1）。
  /// 2026-09-14追加。
  zenKakuGothicNew,

  /// Zen Old Mincho（Zenlab、SIL Open Font License 1.1）。オールドスタイル
  /// 明朝体。2026-09-14追加。
  zenOldMincho,

  /// Zen Maru Gothic（Zenlab、SIL Open Font License 1.1）。丸ゴシック。
  /// 2026-09-14追加。
  zenMaruGothic,

  /// Klee One（SIL Open Font License 1.1）。手書き風の明朝体。2026-09-14追加。
  kleeOne,

  /// Yomogi（SIL Open Font License 1.1）。手書き風フォント。2026-09-14追加。
  yomogi,

  /// Kaisei Decol（SIL Open Font License 1.1）。装飾的な明朝体。
  /// 2026-09-14追加。
  kaiseiDecol,

  /// BIZ UDPMincho（モリサワ、Google Fonts経由、SIL Open Font License 1.1）。
  /// 企画書に元々記載されていたフォントの1つ（2026-09-14実装）。
  bizUdpMincho,

  /// BIZ UDGothic（モリサワ、Google Fonts経由、SIL Open Font License 1.1）。
  /// 企画書に元々記載されていたフォントの1つ（2026-09-14実装）。
  bizUdGothic,

  /// 851チカラヅヨク かなA（8:51:22 pm、非商用/商用利用とも許諾済みの
  /// 独自利用規約）。企画書の「チカラヅヨク」に対応（2026-09-14実装）。
  chikaraDzuyoku851,

  /// 851チカラヨワク（8:51:22 pm、非商用/商用利用とも許諾済みの独自
  /// 利用規約）。企画書の「チカラヨワク」に対応（2026-09-14実装）。
  chikaraYowaku851;

  /// pubspec.yamlに登録したfontFamily名。
  String get fontFamily => switch (this) {
    FontDesign.hannariMincho => 'HannariMincho',
    FontDesign.kagurazaka => 'KHDotKagurazaka16',
    FontDesign.kiwiMaru => 'KiwiMaru',
    FontDesign.shipporiMincho => 'ShipporiMincho',
    FontDesign.notoSansJp => 'NotoSansJP',
    FontDesign.notoSerifJp => 'NotoSerifJP',
    FontDesign.genShinGothic => 'GenShinGothic',
    FontDesign.genJyuuGothic => 'GenJyuuGothic',
    FontDesign.roundedMPlus => 'RoundedMPlus1c',
    FontDesign.gochikakutto851 => 'Gochikakutto851',
    FontDesign.darumadropOne => 'DarumadropOne',
    FontDesign.zenKakuGothicNew => 'ZenKakuGothicNew',
    FontDesign.zenOldMincho => 'ZenOldMincho',
    FontDesign.zenMaruGothic => 'ZenMaruGothic',
    FontDesign.kleeOne => 'KleeOne',
    FontDesign.yomogi => 'Yomogi',
    FontDesign.kaiseiDecol => 'KaiseiDecol',
    FontDesign.bizUdpMincho => 'BIZUDPMincho',
    FontDesign.bizUdGothic => 'BIZUDGothic',
    FontDesign.chikaraDzuyoku851 => 'Chikara851Dzuyoku',
    FontDesign.chikaraYowaku851 => 'Chikara851Yowaku',
  };

  /// 企画書6章「有料プラン『極み』」の「追加フォント10種」に該当するか
  /// （2026-09-06追加）。現時点では極みプラン自体の課金判定ロジックが
  /// 未実装のため、この値は表示上の目印（設定画面のバッジ等）にのみ使い、
  /// 選択自体は誰でも行える。極みプラン本体を実装する際に、ここを見て
  /// 選択を制限する形に変更する想定。2026-09-14に追加した10種は、企画書の
  /// 「追加フォント10種」の対象かどうか未確定のため、ひとまず無料枠のまま
  /// （false）にしている。
  bool get isKiwamiExclusive => switch (this) {
    FontDesign.kiwiMaru => true,
    FontDesign.shipporiMincho => true,
    FontDesign.hannariMincho => false,
    FontDesign.kagurazaka => false,
    FontDesign.notoSansJp => false,
    FontDesign.notoSerifJp => false,
    FontDesign.genShinGothic => false,
    FontDesign.genJyuuGothic => false,
    FontDesign.roundedMPlus => false,
    FontDesign.gochikakutto851 => false,
    FontDesign.darumadropOne => false,
    FontDesign.zenKakuGothicNew => false,
    FontDesign.zenOldMincho => false,
    FontDesign.zenMaruGothic => false,
    FontDesign.kleeOne => false,
    FontDesign.yomogi => false,
    FontDesign.kaiseiDecol => false,
    FontDesign.bizUdpMincho => false,
    FontDesign.bizUdGothic => false,
    FontDesign.chikaraDzuyoku851 => false,
    FontDesign.chikaraYowaku851 => false,
  };

  static FontDesign fromName(String? name) {
    return FontDesign.values.firstWhere(
      (design) => design.name == name,
      orElse: () => FontDesign.notoSansJp,
    );
  }
}
