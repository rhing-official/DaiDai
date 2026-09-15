/// アプリの文字に使うフォント（2026-09-06追加）。端末ごとの個人設定で、
/// フラット・劇画・ガラス全てのUIスタイルの`TextTheme`に適用する
/// （劇画は見出し・ロゴ・カウンター表示のみ固定のAntonを上書き適用する、
/// `GekigaTheme`参照）。
///
/// [standard]（プラットフォーム既定のフォントのまま変更しない選択肢）は
/// 2026-09-14にユーザー指示で廃止した。全ての選択肢が具体的なフォントを
/// 指定する（[fontFamily]が非null）。
///
/// 宣言順は設定画面の表示順そのもの（2026-09-15、ユーザー指示で並び替え）。
/// 「使う人が多そうなものを上に」「提供元が同じものを固めて」の2軸で、
/// 各メンバーのdocコメントに明記した提供元ごとにグループ化した上で
/// グループ単位の知名度順に並べている（Noto→Zenlab→モリサワ(BIZ UD)→
/// 自家製フォント工房→Google Fonts個人制作の手書き系→極み限定2種→
/// 単独のドット/明朝2種→8:51:22 pm→もじワク研究→単独の装飾系2種）。
enum FontDesign {
  /// Noto Sans JP（Google/Adobe、SIL Open Font License 1.1）。角ゴシック
  /// の定番。2026-09-14追加。
  notoSansJp,

  /// Noto Serif JP（Google/Adobe、SIL Open Font License 1.1）。明朝体の
  /// 定番。2026-09-14追加。
  notoSerifJp,

  /// Zen Kaku Gothic New（Zenlab、SIL Open Font License 1.1）。
  /// 2026-09-14追加。
  zenKakuGothicNew,

  /// Zen Maru Gothic（Zenlab、SIL Open Font License 1.1）。丸ゴシック。
  /// 2026-09-14追加。
  zenMaruGothic,

  /// Zen Old Mincho（Zenlab、SIL Open Font License 1.1）。オールドスタイル
  /// 明朝体。2026-09-14追加。
  zenOldMincho,

  /// BIZ UDGothic（モリサワ、Google Fonts経由、SIL Open Font License 1.1）。
  /// 企画書に元々記載されていたフォントの1つ（2026-09-14実装）。
  bizUdGothic,

  /// BIZ UDPMincho（モリサワ、Google Fonts経由、SIL Open Font License 1.1）。
  /// 企画書に元々記載されていたフォントの1つ（2026-09-14実装）。
  bizUdpMincho,

  /// 源真ゴシック（自家製フォント工房、SIL Open Font License 1.1）。
  /// 源ノ角ゴシック（Noto Sans CJK）ベースの角ゴシック。2026-09-14追加。
  genShinGothic,

  /// 源柔ゴシック（自家製フォント工房、SIL Open Font License 1.1）。
  /// 源真ゴシックの丸ゴシック版。2026-09-14追加。
  genJyuuGothic,

  /// 自家製 Rounded M+（自家製フォント工房、M+ FONT LICENSE）。やわらかい
  /// 丸ゴシック。2026-09-14追加。
  roundedMPlus,

  /// Klee One（SIL Open Font License 1.1）。手書き風の明朝体。2026-09-14追加。
  kleeOne,

  /// Yomogi（SIL Open Font License 1.1）。手書き風フォント。2026-09-14追加。
  yomogi,

  /// Kaisei Decol（SIL Open Font License 1.1）。装飾的な明朝体。
  /// 2026-09-14追加。
  kaiseiDecol,

  /// キウイ丸（SIL Open Font License 1.1）。企画書の極みプラン限定
  /// 「追加フォント10種」の1つ（2026-09-06追加、[isKiwamiExclusive]参照）。
  kiwiMaru,

  /// しっぽり明朝（SIL Open Font License 1.1）。企画書の極みプラン限定
  /// 「追加フォント10種」の1つ（2026-09-06追加、[isKiwamiExclusive]参照）。
  shipporiMincho,

  /// KHドットフォント 12神楽坂（SIL Open Font License 1.1）。ドット
  /// （ビットマップ風）の明朝体。
  kagurazaka,

  /// はんなり明朝（IPAフォントライセンスv1.0、IPAex明朝の派生）。
  hannariMincho,

  /// 851ゴチカクット（8:51:22 pm、非商用/商用利用とも許諾済みの独自利用規約）。
  /// カクカクした電機文字風のデザインフォント。2026-09-14追加。
  gochikakutto851,

  /// 851チカラヅヨク かなA（8:51:22 pm、非商用/商用利用とも許諾済みの
  /// 独自利用規約）。企画書の「チカラヅヨク」に対応（2026-09-14実装）。
  chikaraDzuyoku851,

  /// 851チカラヨワク（8:51:22 pm、非商用/商用利用とも許諾済みの独自
  /// 利用規約）。企画書の「チカラヨワク」に対応（2026-09-14実装）。
  chikaraYowaku851,

  /// マキナス（4 Flat、もじワク研究、フリーフォント・商用利用可。
  /// アプリへの組み込みは利用規約の「文字編集機能・システムフォントとして
  /// の使用」に該当し許諾済み）。手書きの線を意識したデザインフォント。
  /// ユーザーから依頼のあった「マキナス Scrap」は配布元サイトで廃盤に
  /// なっており入手できなかったため、同シリーズの現行版で代用
  /// （2026-09-15、ユーザー確認済み）。
  makinas4Flat,

  /// ピグモ01（もじワク研究、フリーフォント・商用利用可、makinas4Flatと
  /// 同じ利用規約）。1文字ごとに形の違う遊び心のあるデザインフォント。
  /// 2026-09-15追加。
  pigmo01,

  /// ポプらむ☆キュート（もじワク研究、フリーフォント・商用利用可、
  /// makinas4Flatと同じ利用規約）。1970〜90年代流行の丸文字を再現した
  /// フォント。2026-09-15追加。
  popRumCute,

  /// 黒薔薇シンデレラ（MODI工場、M+ FONTS派生・フリーフォント・商用利用可。
  /// アプリへの組み込みは配布元サイトのライセンス概要「M+派生：アプリ等への
  /// フォント埋め込み可」に該当）。ゴシック体寄りの手書き風フォント。
  /// 2026-09-15追加。
  kurobaraCinderella,

  /// けいふぉんと！（Do-Font、Apache License 2.0）。アニメロゴ風の
  /// ポップなデザインフォント。ひらがな・カタカナ以外は源真ゴシック等の
  /// オープンソースフォント由来。2026-09-15追加。
  keifont;

  /// pubspec.yamlに登録したfontFamily名。
  String get fontFamily => switch (this) {
    FontDesign.notoSansJp => 'NotoSansJP',
    FontDesign.notoSerifJp => 'NotoSerifJP',
    FontDesign.zenKakuGothicNew => 'ZenKakuGothicNew',
    FontDesign.zenMaruGothic => 'ZenMaruGothic',
    FontDesign.zenOldMincho => 'ZenOldMincho',
    FontDesign.bizUdGothic => 'BIZUDGothic',
    FontDesign.bizUdpMincho => 'BIZUDPMincho',
    FontDesign.genShinGothic => 'GenShinGothic',
    FontDesign.genJyuuGothic => 'GenJyuuGothic',
    FontDesign.roundedMPlus => 'RoundedMPlus1c',
    FontDesign.kleeOne => 'KleeOne',
    FontDesign.yomogi => 'Yomogi',
    FontDesign.kaiseiDecol => 'KaiseiDecol',
    FontDesign.kiwiMaru => 'KiwiMaru',
    FontDesign.shipporiMincho => 'ShipporiMincho',
    FontDesign.kagurazaka => 'KHDotKagurazaka16',
    FontDesign.hannariMincho => 'HannariMincho',
    FontDesign.gochikakutto851 => 'Gochikakutto851',
    FontDesign.chikaraDzuyoku851 => 'Chikara851Dzuyoku',
    FontDesign.chikaraYowaku851 => 'Chikara851Yowaku',
    FontDesign.makinas4Flat => 'Makinas4Flat',
    FontDesign.pigmo01 => 'Pigmo01',
    FontDesign.popRumCute => 'PopRumCute',
    FontDesign.kurobaraCinderella => 'KurobaraCinderella',
    FontDesign.keifont => 'Keifont',
  };

  /// 企画書6章「有料プラン『極み』」の「追加フォント10種」に該当するか
  /// （2026-09-06追加）。現時点では極みプラン自体の課金判定ロジックが
  /// 未実装のため、この値は表示上の目印（設定画面のバッジ等）にのみ使い、
  /// 選択自体は誰でも行える。極みプラン本体を実装する際に、ここを見て
  /// 選択を制限する形に変更する想定。2026-09-14に追加した10種は、企画書の
  /// 「追加フォント10種」の対象かどうか未確定のため、ひとまず無料枠のまま
  /// （false）にしている。
  bool get isKiwamiExclusive => switch (this) {
    FontDesign.notoSansJp => false,
    FontDesign.notoSerifJp => false,
    FontDesign.zenKakuGothicNew => false,
    FontDesign.zenMaruGothic => false,
    FontDesign.zenOldMincho => false,
    FontDesign.bizUdGothic => false,
    FontDesign.bizUdpMincho => false,
    FontDesign.genShinGothic => false,
    FontDesign.genJyuuGothic => false,
    FontDesign.roundedMPlus => false,
    FontDesign.kleeOne => false,
    FontDesign.yomogi => false,
    FontDesign.kaiseiDecol => false,
    FontDesign.kiwiMaru => true,
    FontDesign.shipporiMincho => true,
    FontDesign.kagurazaka => false,
    FontDesign.hannariMincho => false,
    FontDesign.gochikakutto851 => false,
    FontDesign.chikaraDzuyoku851 => false,
    FontDesign.chikaraYowaku851 => false,
    FontDesign.makinas4Flat => false,
    FontDesign.pigmo01 => false,
    FontDesign.popRumCute => false,
    FontDesign.kurobaraCinderella => false,
    FontDesign.keifont => false,
  };

  static FontDesign fromName(String? name) {
    return FontDesign.values.firstWhere(
      (design) => design.name == name,
      orElse: () => FontDesign.notoSansJp,
    );
  }
}
