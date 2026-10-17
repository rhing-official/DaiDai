import 'app_locale.dart';

/// 日本の都道府県（居住地アンケート用、2026-10-16追加）。座標は県庁所在地で、
/// 伝書鳩の距離計算（GPSは使わず自己申告の居住地から代表座標を引く）に使う。
class Prefecture {
  const Prefecture(this.code, this.ja, this.en, this.lat, this.lng);

  /// ISO 3166-2:JPの下2桁（`JP-13`なら`13`）。保存時は`JP-13`形式にする。
  final String code;
  final String ja;
  final String en;
  final double lat;
  final double lng;

  String get isoCode => 'JP-$code';

  /// 日本語以外の表示言語では、ローマ字表記（[en]）を共通で使う（ラテン文字圏の
  /// 言語では日本の都道府県名はローマ字で書くのが標準のため、言語ごとの訳は持たない）。
  String nameOf(AppLocale locale) => switch (locale) {
    AppLocale.japanese => ja,
    _ => en,
  };
}

const prefectures = <Prefecture>[
  Prefecture('01', '北海道', 'Hokkaido', 43.06, 141.35),
  Prefecture('02', '青森県', 'Aomori', 40.82, 140.74),
  Prefecture('03', '岩手県', 'Iwate', 39.70, 141.15),
  Prefecture('04', '宮城県', 'Miyagi', 38.27, 140.87),
  Prefecture('05', '秋田県', 'Akita', 39.72, 140.10),
  Prefecture('06', '山形県', 'Yamagata', 38.24, 140.36),
  Prefecture('07', '福島県', 'Fukushima', 37.75, 140.47),
  Prefecture('08', '茨城県', 'Ibaraki', 36.34, 140.45),
  Prefecture('09', '栃木県', 'Tochigi', 36.57, 139.88),
  Prefecture('10', '群馬県', 'Gunma', 36.39, 139.06),
  Prefecture('11', '埼玉県', 'Saitama', 35.86, 139.65),
  Prefecture('12', '千葉県', 'Chiba', 35.61, 140.12),
  Prefecture('13', '東京都', 'Tokyo', 35.69, 139.69),
  Prefecture('14', '神奈川県', 'Kanagawa', 35.45, 139.64),
  Prefecture('15', '新潟県', 'Niigata', 37.90, 139.02),
  Prefecture('16', '富山県', 'Toyama', 36.70, 137.21),
  Prefecture('17', '石川県', 'Ishikawa', 36.59, 136.63),
  Prefecture('18', '福井県', 'Fukui', 36.07, 136.22),
  Prefecture('19', '山梨県', 'Yamanashi', 35.66, 138.57),
  Prefecture('20', '長野県', 'Nagano', 36.65, 138.18),
  Prefecture('21', '岐阜県', 'Gifu', 35.39, 136.72),
  Prefecture('22', '静岡県', 'Shizuoka', 34.98, 138.38),
  Prefecture('23', '愛知県', 'Aichi', 35.18, 136.91),
  Prefecture('24', '三重県', 'Mie', 34.73, 136.51),
  Prefecture('25', '滋賀県', 'Shiga', 35.00, 135.87),
  Prefecture('26', '京都府', 'Kyoto', 35.02, 135.76),
  Prefecture('27', '大阪府', 'Osaka', 34.69, 135.52),
  Prefecture('28', '兵庫県', 'Hyogo', 34.69, 135.18),
  Prefecture('29', '奈良県', 'Nara', 34.69, 135.83),
  Prefecture('30', '和歌山県', 'Wakayama', 34.23, 135.17),
  Prefecture('31', '鳥取県', 'Tottori', 35.50, 134.24),
  Prefecture('32', '島根県', 'Shimane', 35.47, 133.05),
  Prefecture('33', '岡山県', 'Okayama', 34.66, 133.93),
  Prefecture('34', '広島県', 'Hiroshima', 34.40, 132.46),
  Prefecture('35', '山口県', 'Yamaguchi', 34.19, 131.47),
  Prefecture('36', '徳島県', 'Tokushima', 34.07, 134.56),
  Prefecture('37', '香川県', 'Kagawa', 34.34, 134.04),
  Prefecture('38', '愛媛県', 'Ehime', 33.84, 132.77),
  Prefecture('39', '高知県', 'Kochi', 33.56, 133.53),
  Prefecture('40', '福岡県', 'Fukuoka', 33.61, 130.42),
  Prefecture('41', '佐賀県', 'Saga', 33.25, 130.30),
  Prefecture('42', '長崎県', 'Nagasaki', 32.74, 129.87),
  Prefecture('43', '熊本県', 'Kumamoto', 32.79, 130.74),
  Prefecture('44', '大分県', 'Oita', 33.24, 131.61),
  Prefecture('45', '宮崎県', 'Miyazaki', 31.91, 131.42),
  Prefecture('46', '鹿児島県', 'Kagoshima', 31.56, 130.56),
  Prefecture('47', '沖縄県', 'Okinawa', 26.21, 127.68),
];

/// `JP-13`形式のコードから都道府県を引く。不明なら`null`。
Prefecture? prefectureByCode(String? isoCode) {
  if (isoCode == null) return null;
  for (final p in prefectures) {
    if (p.isoCode == isoCode) return p;
  }
  return null;
}
