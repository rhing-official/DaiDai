import 'app_locale.dart';
import 'country_names_fr.dart';

/// 居住地アンケート用の国データ（2026-10-16追加）。座標は首都（国によっては
/// 最大都市）で、伝書鳩の距離計算に使う。GPSは使わず、自己申告の国から
/// 代表座標を引く。
class Country {
  const Country(
    this.code,
    this.ja,
    this.en,
    this.lat,
    this.lng,
    this.timeZone, {
    this.timeZones = const [],
  });

  /// ISO 3166-1 alpha-2。
  final String code;
  final String ja;
  final String en;
  final double lat;
  final double lng;

  /// 既定のタイムゾーン（IANA名）。タイムゾーンを聞かなかった場合に使う。
  final String timeZone;

  /// 国内に時差が複数ある国の選択肢（IANA名、既定の[timeZone]を含む）。
  /// 空なら時差は1つとして扱い、タイムゾーンは聞かない。
  final List<String> timeZones;

  bool get hasMultipleTimeZones => timeZones.length > 1;

  /// 表示言語に合わせた国名。日本語・英語は自身のフィールド、それ以外は
  /// 言語別の対応表（[countryNamesOf]）から引き、無ければ英語にする。
  String nameOf(AppLocale locale) {
    if (locale == AppLocale.japanese) return ja;
    return countryNamesOf(locale)?[code] ?? en;
  }

  /// 検索に使う名前（日本語・英語・表示言語の名前）。
  List<String> searchNames(AppLocale locale) =>
      {ja, en, nameOf(locale)}.toList();
}

/// 日本語・英語以外の表示言語の国名（ISO 3166-1 alpha-2→名前）。言語を足したとき
/// 抜けないよう、switch式（網羅性エラー）で言語ごとの対応表を返す。日本語・英語は
/// [Country]自身が持つため`null`。
Map<String, String>? countryNamesOf(AppLocale locale) {
  return switch (locale) {
    AppLocale.japanese => null,
    AppLocale.britishEnglish => null,
    AppLocale.french => countryNamesFr,
  };
}

/// 日本を先頭に、地域ごとに並べている。
const countries = <Country>[
  // 日本・東アジア
  Country('JP', '日本', 'Japan', 35.7, 139.7, 'Asia/Tokyo'),
  Country('KR', '韓国', 'South Korea', 37.6, 127.0, 'Asia/Seoul'),
  Country('KP', '北朝鮮', 'North Korea', 39.0, 125.8, 'Asia/Pyongyang'),
  Country('CN', '中国', 'China', 39.9, 116.4, 'Asia/Shanghai'),
  Country('TW', '台湾', 'Taiwan', 25.0, 121.5, 'Asia/Taipei'),
  Country('HK', '香港', 'Hong Kong', 22.3, 114.2, 'Asia/Hong_Kong'),
  Country('MO', 'マカオ', 'Macao', 22.2, 113.5, 'Asia/Macau'),
  Country(
    'MN',
    'モンゴル',
    'Mongolia',
    47.9,
    106.9,
    'Asia/Ulaanbaatar',
    timeZones: ['Asia/Ulaanbaatar', 'Asia/Hovd'],
  ),
  // 東南アジア
  Country('VN', 'ベトナム', 'Vietnam', 21.0, 105.8, 'Asia/Ho_Chi_Minh'),
  Country('TH', 'タイ', 'Thailand', 13.8, 100.5, 'Asia/Bangkok'),
  Country('LA', 'ラオス', 'Laos', 18.0, 102.6, 'Asia/Vientiane'),
  Country('KH', 'カンボジア', 'Cambodia', 11.6, 104.9, 'Asia/Phnom_Penh'),
  Country('MM', 'ミャンマー', 'Myanmar', 19.8, 96.1, 'Asia/Yangon'),
  Country('MY', 'マレーシア', 'Malaysia', 3.1, 101.7, 'Asia/Kuala_Lumpur'),
  Country('SG', 'シンガポール', 'Singapore', 1.3, 103.8, 'Asia/Singapore'),
  Country('BN', 'ブルネイ', 'Brunei', 4.9, 114.9, 'Asia/Brunei'),
  Country(
    'ID',
    'インドネシア',
    'Indonesia',
    -6.2,
    106.8,
    'Asia/Jakarta',
    timeZones: ['Asia/Jakarta', 'Asia/Makassar', 'Asia/Jayapura'],
  ),
  Country('PH', 'フィリピン', 'Philippines', 14.6, 121.0, 'Asia/Manila'),
  Country('TL', '東ティモール', 'Timor-Leste', -8.6, 125.6, 'Asia/Dili'),
  // 南アジア
  Country('IN', 'インド', 'India', 28.6, 77.2, 'Asia/Kolkata'),
  Country('PK', 'パキスタン', 'Pakistan', 33.7, 73.1, 'Asia/Karachi'),
  Country('BD', 'バングラデシュ', 'Bangladesh', 23.8, 90.4, 'Asia/Dhaka'),
  Country('LK', 'スリランカ', 'Sri Lanka', 6.9, 79.9, 'Asia/Colombo'),
  Country('NP', 'ネパール', 'Nepal', 27.7, 85.3, 'Asia/Kathmandu'),
  Country('BT', 'ブータン', 'Bhutan', 27.5, 89.6, 'Asia/Thimphu'),
  Country('MV', 'モルディブ', 'Maldives', 4.2, 73.5, 'Indian/Maldives'),
  Country('AF', 'アフガニスタン', 'Afghanistan', 34.5, 69.2, 'Asia/Kabul'),
  // 中央アジア・コーカサス
  Country(
    'KZ',
    'カザフスタン',
    'Kazakhstan',
    51.2,
    71.4,
    'Asia/Almaty',
    timeZones: ['Asia/Almaty', 'Asia/Aqtobe', 'Asia/Aqtau'],
  ),
  Country('UZ', 'ウズベキスタン', 'Uzbekistan', 41.3, 69.3, 'Asia/Tashkent'),
  Country('TM', 'トルクメニスタン', 'Turkmenistan', 37.9, 58.4, 'Asia/Ashgabat'),
  Country('TJ', 'タジキスタン', 'Tajikistan', 38.6, 68.8, 'Asia/Dushanbe'),
  Country('KG', 'キルギス', 'Kyrgyzstan', 42.9, 74.6, 'Asia/Bishkek'),
  Country('GE', 'ジョージア', 'Georgia', 41.7, 44.8, 'Asia/Tbilisi'),
  Country('AM', 'アルメニア', 'Armenia', 40.2, 44.5, 'Asia/Yerevan'),
  Country('AZ', 'アゼルバイジャン', 'Azerbaijan', 40.4, 49.9, 'Asia/Baku'),
  // 中東
  Country('TR', 'トルコ', 'Türkiye', 39.9, 32.9, 'Europe/Istanbul'),
  Country('IR', 'イラン', 'Iran', 35.7, 51.4, 'Asia/Tehran'),
  Country('IQ', 'イラク', 'Iraq', 33.3, 44.4, 'Asia/Baghdad'),
  Country('SY', 'シリア', 'Syria', 33.5, 36.3, 'Asia/Damascus'),
  Country('LB', 'レバノン', 'Lebanon', 33.9, 35.5, 'Asia/Beirut'),
  Country('IL', 'イスラエル', 'Israel', 31.8, 35.2, 'Asia/Jerusalem'),
  Country('PS', 'パレスチナ', 'Palestine', 31.9, 35.2, 'Asia/Hebron'),
  Country('JO', 'ヨルダン', 'Jordan', 31.9, 35.9, 'Asia/Amman'),
  Country('SA', 'サウジアラビア', 'Saudi Arabia', 24.7, 46.7, 'Asia/Riyadh'),
  Country('YE', 'イエメン', 'Yemen', 15.4, 44.2, 'Asia/Aden'),
  Country('OM', 'オマーン', 'Oman', 23.6, 58.4, 'Asia/Muscat'),
  Country('AE', 'アラブ首長国連邦', 'United Arab Emirates', 24.5, 54.4, 'Asia/Dubai'),
  Country('QA', 'カタール', 'Qatar', 25.3, 51.5, 'Asia/Qatar'),
  Country('BH', 'バーレーン', 'Bahrain', 26.2, 50.6, 'Asia/Bahrain'),
  Country('KW', 'クウェート', 'Kuwait', 29.4, 48.0, 'Asia/Kuwait'),
  Country('CY', 'キプロス', 'Cyprus', 35.2, 33.4, 'Asia/Nicosia'),
  // 西ヨーロッパ
  Country('GB', 'イギリス', 'United Kingdom', 51.5, -0.1, 'Europe/London'),
  Country('IE', 'アイルランド', 'Ireland', 53.3, -6.3, 'Europe/Dublin'),
  Country('FR', 'フランス', 'France', 48.9, 2.4, 'Europe/Paris'),
  Country('DE', 'ドイツ', 'Germany', 52.5, 13.4, 'Europe/Berlin'),
  Country('NL', 'オランダ', 'Netherlands', 52.4, 4.9, 'Europe/Amsterdam'),
  Country('BE', 'ベルギー', 'Belgium', 50.8, 4.4, 'Europe/Brussels'),
  Country('LU', 'ルクセンブルク', 'Luxembourg', 49.6, 6.1, 'Europe/Luxembourg'),
  Country('CH', 'スイス', 'Switzerland', 46.9, 7.4, 'Europe/Zurich'),
  Country('AT', 'オーストリア', 'Austria', 48.2, 16.4, 'Europe/Vienna'),
  Country('LI', 'リヒテンシュタイン', 'Liechtenstein', 47.1, 9.5, 'Europe/Vaduz'),
  Country('MC', 'モナコ', 'Monaco', 43.7, 7.4, 'Europe/Monaco'),
  // 南ヨーロッパ
  Country('IT', 'イタリア', 'Italy', 41.9, 12.5, 'Europe/Rome'),
  Country(
    'ES',
    'スペイン',
    'Spain',
    40.4,
    -3.7,
    'Europe/Madrid',
    timeZones: ['Europe/Madrid', 'Atlantic/Canary'],
  ),
  Country(
    'PT',
    'ポルトガル',
    'Portugal',
    38.7,
    -9.1,
    'Europe/Lisbon',
    timeZones: ['Europe/Lisbon', 'Atlantic/Azores'],
  ),
  Country('AD', 'アンドラ', 'Andorra', 42.5, 1.5, 'Europe/Andorra'),
  Country('SM', 'サンマリノ', 'San Marino', 43.9, 12.4, 'Europe/San_Marino'),
  Country('VA', 'バチカン', 'Vatican City', 41.9, 12.5, 'Europe/Vatican'),
  Country('MT', 'マルタ', 'Malta', 35.9, 14.5, 'Europe/Malta'),
  Country('GR', 'ギリシャ', 'Greece', 38.0, 23.7, 'Europe/Athens'),
  // 北ヨーロッパ
  Country('DK', 'デンマーク', 'Denmark', 55.7, 12.6, 'Europe/Copenhagen'),
  Country('SE', 'スウェーデン', 'Sweden', 59.3, 18.1, 'Europe/Stockholm'),
  Country('NO', 'ノルウェー', 'Norway', 59.9, 10.8, 'Europe/Oslo'),
  Country('FI', 'フィンランド', 'Finland', 60.2, 24.9, 'Europe/Helsinki'),
  Country('IS', 'アイスランド', 'Iceland', 64.1, -21.9, 'Atlantic/Reykjavik'),
  Country('EE', 'エストニア', 'Estonia', 59.4, 24.7, 'Europe/Tallinn'),
  Country('LV', 'ラトビア', 'Latvia', 56.9, 24.1, 'Europe/Riga'),
  Country('LT', 'リトアニア', 'Lithuania', 54.7, 25.3, 'Europe/Vilnius'),
  // 東ヨーロッパ・バルカン
  Country('PL', 'ポーランド', 'Poland', 52.2, 21.0, 'Europe/Warsaw'),
  Country('CZ', 'チェコ', 'Czechia', 50.1, 14.4, 'Europe/Prague'),
  Country('SK', 'スロバキア', 'Slovakia', 48.1, 17.1, 'Europe/Bratislava'),
  Country('HU', 'ハンガリー', 'Hungary', 47.5, 19.0, 'Europe/Budapest'),
  Country('SI', 'スロベニア', 'Slovenia', 46.1, 14.5, 'Europe/Ljubljana'),
  Country('HR', 'クロアチア', 'Croatia', 45.8, 16.0, 'Europe/Zagreb'),
  Country(
    'BA',
    'ボスニア・ヘルツェゴビナ',
    'Bosnia and Herzegovina',
    43.9,
    18.4,
    'Europe/Sarajevo',
  ),
  Country('RS', 'セルビア', 'Serbia', 44.8, 20.5, 'Europe/Belgrade'),
  Country('ME', 'モンテネグロ', 'Montenegro', 42.4, 19.3, 'Europe/Podgorica'),
  Country('MK', '北マケドニア', 'North Macedonia', 42.0, 21.4, 'Europe/Skopje'),
  Country('AL', 'アルバニア', 'Albania', 41.3, 19.8, 'Europe/Tirane'),
  Country('BG', 'ブルガリア', 'Bulgaria', 42.7, 23.3, 'Europe/Sofia'),
  Country('RO', 'ルーマニア', 'Romania', 44.4, 26.1, 'Europe/Bucharest'),
  Country('MD', 'モルドバ', 'Moldova', 47.0, 28.9, 'Europe/Chisinau'),
  Country('UA', 'ウクライナ', 'Ukraine', 50.5, 30.5, 'Europe/Kyiv'),
  Country('BY', 'ベラルーシ', 'Belarus', 53.9, 27.6, 'Europe/Minsk'),
  Country(
    'RU',
    'ロシア',
    'Russia',
    55.8,
    37.6,
    'Europe/Moscow',
    timeZones: [
      'Europe/Kaliningrad',
      'Europe/Moscow',
      'Europe/Samara',
      'Asia/Yekaterinburg',
      'Asia/Omsk',
      'Asia/Krasnoyarsk',
      'Asia/Irkutsk',
      'Asia/Yakutsk',
      'Asia/Vladivostok',
      'Asia/Magadan',
      'Asia/Kamchatka',
    ],
  ),
  // 北アフリカ
  Country('EG', 'エジプト', 'Egypt', 30.0, 31.2, 'Africa/Cairo'),
  Country('LY', 'リビア', 'Libya', 32.9, 13.2, 'Africa/Tripoli'),
  Country('TN', 'チュニジア', 'Tunisia', 36.8, 10.2, 'Africa/Tunis'),
  Country('DZ', 'アルジェリア', 'Algeria', 36.8, 3.1, 'Africa/Algiers'),
  Country('MA', 'モロッコ', 'Morocco', 34.0, -6.8, 'Africa/Casablanca'),
  Country('SD', 'スーダン', 'Sudan', 15.6, 32.5, 'Africa/Khartoum'),
  Country('SS', '南スーダン', 'South Sudan', 4.9, 31.6, 'Africa/Juba'),
  // 西アフリカ
  Country('MR', 'モーリタニア', 'Mauritania', 18.1, -16.0, 'Africa/Nouakchott'),
  Country('SN', 'セネガル', 'Senegal', 14.7, -17.5, 'Africa/Dakar'),
  Country('GM', 'ガンビア', 'Gambia', 13.5, -16.6, 'Africa/Banjul'),
  Country('GW', 'ギニアビサウ', 'Guinea-Bissau', 11.9, -15.6, 'Africa/Bissau'),
  Country('GN', 'ギニア', 'Guinea', 9.5, -13.7, 'Africa/Conakry'),
  Country('SL', 'シエラレオネ', 'Sierra Leone', 8.5, -13.2, 'Africa/Freetown'),
  Country('LR', 'リベリア', 'Liberia', 6.3, -10.8, 'Africa/Monrovia'),
  Country('CI', 'コートジボワール', "Côte d'Ivoire", 6.8, -5.3, 'Africa/Abidjan'),
  Country('ML', 'マリ', 'Mali', 12.6, -8.0, 'Africa/Bamako'),
  Country('BF', 'ブルキナファソ', 'Burkina Faso', 12.4, -1.5, 'Africa/Ouagadougou'),
  Country('GH', 'ガーナ', 'Ghana', 5.6, -0.2, 'Africa/Accra'),
  Country('TG', 'トーゴ', 'Togo', 6.1, 1.2, 'Africa/Lome'),
  Country('BJ', 'ベナン', 'Benin', 6.5, 2.6, 'Africa/Porto-Novo'),
  Country('NE', 'ニジェール', 'Niger', 13.5, 2.1, 'Africa/Niamey'),
  Country('NG', 'ナイジェリア', 'Nigeria', 9.1, 7.5, 'Africa/Lagos'),
  Country('CV', 'カーボベルデ', 'Cabo Verde', 14.9, -23.5, 'Atlantic/Cape_Verde'),
  // 中部アフリカ
  Country('TD', 'チャド', 'Chad', 12.1, 15.0, 'Africa/Ndjamena'),
  Country('CM', 'カメルーン', 'Cameroon', 3.9, 11.5, 'Africa/Douala'),
  Country(
    'CF',
    '中央アフリカ',
    'Central African Republic',
    4.4,
    18.6,
    'Africa/Bangui',
  ),
  Country('GQ', '赤道ギニア', 'Equatorial Guinea', 3.8, 8.8, 'Africa/Malabo'),
  Country('GA', 'ガボン', 'Gabon', 0.4, 9.5, 'Africa/Libreville'),
  Country(
    'CG',
    'コンゴ共和国',
    'Republic of the Congo',
    -4.3,
    15.3,
    'Africa/Brazzaville',
  ),
  Country(
    'CD',
    'コンゴ民主共和国',
    'DR Congo',
    -4.3,
    15.3,
    'Africa/Kinshasa',
    timeZones: ['Africa/Kinshasa', 'Africa/Lubumbashi'],
  ),
  Country('AO', 'アンゴラ', 'Angola', -8.8, 13.2, 'Africa/Luanda'),
  Country(
    'ST',
    'サントメ・プリンシペ',
    'São Tomé and Príncipe',
    0.3,
    6.7,
    'Africa/Sao_Tome',
  ),
  // 東アフリカ
  Country('ER', 'エリトリア', 'Eritrea', 15.3, 38.9, 'Africa/Asmara'),
  Country('ET', 'エチオピア', 'Ethiopia', 9.0, 38.7, 'Africa/Addis_Ababa'),
  Country('DJ', 'ジブチ', 'Djibouti', 11.6, 43.1, 'Africa/Djibouti'),
  Country('SO', 'ソマリア', 'Somalia', 2.0, 45.3, 'Africa/Mogadishu'),
  Country('KE', 'ケニア', 'Kenya', -1.3, 36.8, 'Africa/Nairobi'),
  Country('UG', 'ウガンダ', 'Uganda', 0.3, 32.6, 'Africa/Kampala'),
  Country('TZ', 'タンザニア', 'Tanzania', -6.2, 35.7, 'Africa/Dar_es_Salaam'),
  Country('RW', 'ルワンダ', 'Rwanda', -1.9, 30.1, 'Africa/Kigali'),
  Country('BI', 'ブルンジ', 'Burundi', -3.4, 29.9, 'Africa/Bujumbura'),
  // 南部アフリカ・インド洋
  Country('MW', 'マラウイ', 'Malawi', -14.0, 33.8, 'Africa/Blantyre'),
  Country('ZM', 'ザンビア', 'Zambia', -15.4, 28.3, 'Africa/Lusaka'),
  Country('ZW', 'ジンバブエ', 'Zimbabwe', -17.8, 31.0, 'Africa/Harare'),
  Country('MZ', 'モザンビーク', 'Mozambique', -26.0, 32.6, 'Africa/Maputo'),
  Country('MG', 'マダガスカル', 'Madagascar', -18.9, 47.5, 'Indian/Antananarivo'),
  Country('MU', 'モーリシャス', 'Mauritius', -20.2, 57.5, 'Indian/Mauritius'),
  Country('SC', 'セーシェル', 'Seychelles', -4.6, 55.5, 'Indian/Mahe'),
  Country('KM', 'コモロ', 'Comoros', -11.7, 43.3, 'Indian/Comoro'),
  Country('NA', 'ナミビア', 'Namibia', -22.6, 17.1, 'Africa/Windhoek'),
  Country('BW', 'ボツワナ', 'Botswana', -24.7, 25.9, 'Africa/Gaborone'),
  Country('ZA', '南アフリカ', 'South Africa', -25.7, 28.2, 'Africa/Johannesburg'),
  Country('LS', 'レソト', 'Lesotho', -29.3, 27.5, 'Africa/Maseru'),
  Country('SZ', 'エスワティニ', 'Eswatini', -26.3, 31.1, 'Africa/Mbabane'),
  // 北アメリカ
  Country(
    'US',
    'アメリカ合衆国',
    'United States',
    38.9,
    -77.0,
    'America/New_York',
    timeZones: [
      'America/New_York',
      'America/Chicago',
      'America/Denver',
      'America/Phoenix',
      'America/Los_Angeles',
      'America/Anchorage',
      'Pacific/Honolulu',
    ],
  ),
  Country(
    'CA',
    'カナダ',
    'Canada',
    45.4,
    -75.7,
    'America/Toronto',
    timeZones: [
      'America/St_Johns',
      'America/Halifax',
      'America/Toronto',
      'America/Winnipeg',
      'America/Edmonton',
      'America/Vancouver',
    ],
  ),
  Country(
    'MX',
    'メキシコ',
    'Mexico',
    19.4,
    -99.1,
    'America/Mexico_City',
    timeZones: [
      'America/Cancun',
      'America/Mexico_City',
      'America/Chihuahua',
      'America/Mazatlan',
      'America/Tijuana',
    ],
  ),
  Country('PR', 'プエルトリコ', 'Puerto Rico', 18.5, -66.1, 'America/Puerto_Rico'),
  Country('GL', 'グリーンランド', 'Greenland', 64.2, -51.7, 'America/Nuuk'),
  // 中央アメリカ・カリブ海
  Country('GT', 'グアテマラ', 'Guatemala', 14.6, -90.5, 'America/Guatemala'),
  Country('BZ', 'ベリーズ', 'Belize', 17.3, -88.8, 'America/Belize'),
  Country('SV', 'エルサルバドル', 'El Salvador', 13.7, -89.2, 'America/El_Salvador'),
  Country('HN', 'ホンジュラス', 'Honduras', 14.1, -87.2, 'America/Tegucigalpa'),
  Country('NI', 'ニカラグア', 'Nicaragua', 12.1, -86.3, 'America/Managua'),
  Country('CR', 'コスタリカ', 'Costa Rica', 9.9, -84.1, 'America/Costa_Rica'),
  Country('PA', 'パナマ', 'Panama', 9.0, -79.5, 'America/Panama'),
  Country('CU', 'キューバ', 'Cuba', 23.1, -82.4, 'America/Havana'),
  Country('JM', 'ジャマイカ', 'Jamaica', 18.0, -76.8, 'America/Jamaica'),
  Country('HT', 'ハイチ', 'Haiti', 18.5, -72.3, 'America/Port-au-Prince'),
  Country(
    'DO',
    'ドミニカ共和国',
    'Dominican Republic',
    18.5,
    -69.9,
    'America/Santo_Domingo',
  ),
  Country('BS', 'バハマ', 'Bahamas', 25.0, -77.4, 'America/Nassau'),
  Country('BB', 'バルバドス', 'Barbados', 13.1, -59.6, 'America/Barbados'),
  Country(
    'TT',
    'トリニダード・トバゴ',
    'Trinidad and Tobago',
    10.7,
    -61.5,
    'America/Port_of_Spain',
  ),
  Country(
    'AG',
    'アンティグア・バーブーダ',
    'Antigua and Barbuda',
    17.1,
    -61.8,
    'America/Antigua',
  ),
  Country('DM', 'ドミニカ国', 'Dominica', 15.3, -61.4, 'America/Dominica'),
  Country('LC', 'セントルシア', 'Saint Lucia', 14.0, -61.0, 'America/St_Lucia'),
  Country(
    'VC',
    'セントビンセント・グレナディーン',
    'Saint Vincent and the Grenadines',
    13.2,
    -61.2,
    'America/St_Vincent',
  ),
  Country('GD', 'グレナダ', 'Grenada', 12.1, -61.8, 'America/Grenada'),
  Country(
    'KN',
    'セントクリストファー・ネイビス',
    'Saint Kitts and Nevis',
    17.3,
    -62.7,
    'America/St_Kitts',
  ),
  // 南アメリカ
  Country(
    'BR',
    'ブラジル',
    'Brazil',
    -15.8,
    -47.9,
    'America/Sao_Paulo',
    timeZones: [
      'America/Noronha',
      'America/Sao_Paulo',
      'America/Manaus',
      'America/Rio_Branco',
    ],
  ),
  Country(
    'AR',
    'アルゼンチン',
    'Argentina',
    -34.6,
    -58.4,
    'America/Argentina/Buenos_Aires',
  ),
  Country(
    'CL',
    'チリ',
    'Chile',
    -33.4,
    -70.7,
    'America/Santiago',
    timeZones: ['America/Santiago', 'America/Punta_Arenas', 'Pacific/Easter'],
  ),
  Country('UY', 'ウルグアイ', 'Uruguay', -34.9, -56.2, 'America/Montevideo'),
  Country('PY', 'パラグアイ', 'Paraguay', -25.3, -57.6, 'America/Asuncion'),
  Country('BO', 'ボリビア', 'Bolivia', -16.5, -68.1, 'America/La_Paz'),
  Country('PE', 'ペルー', 'Peru', -12.0, -77.0, 'America/Lima'),
  Country(
    'EC',
    'エクアドル',
    'Ecuador',
    -0.2,
    -78.5,
    'America/Guayaquil',
    timeZones: ['America/Guayaquil', 'Pacific/Galapagos'],
  ),
  Country('CO', 'コロンビア', 'Colombia', 4.7, -74.1, 'America/Bogota'),
  Country('VE', 'ベネズエラ', 'Venezuela', 10.5, -66.9, 'America/Caracas'),
  Country('GY', 'ガイアナ', 'Guyana', 6.8, -58.2, 'America/Guyana'),
  Country('SR', 'スリナム', 'Suriname', 5.9, -55.2, 'America/Paramaribo'),
  // オセアニア
  Country(
    'AU',
    'オーストラリア',
    'Australia',
    -35.3,
    149.1,
    'Australia/Sydney',
    timeZones: [
      'Australia/Sydney',
      'Australia/Brisbane',
      'Australia/Adelaide',
      'Australia/Darwin',
      'Australia/Perth',
      'Australia/Hobart',
    ],
  ),
  Country(
    'NZ',
    'ニュージーランド',
    'New Zealand',
    -41.3,
    174.8,
    'Pacific/Auckland',
    timeZones: ['Pacific/Auckland', 'Pacific/Chatham'],
  ),
  Country('FJ', 'フィジー', 'Fiji', -18.1, 178.4, 'Pacific/Fiji'),
  Country(
    'PG',
    'パプアニューギニア',
    'Papua New Guinea',
    -9.4,
    147.2,
    'Pacific/Port_Moresby',
  ),
  Country(
    'SB',
    'ソロモン諸島',
    'Solomon Islands',
    -9.4,
    160.0,
    'Pacific/Guadalcanal',
  ),
  Country('VU', 'バヌアツ', 'Vanuatu', -17.7, 168.3, 'Pacific/Efate'),
  Country('NC', 'ニューカレドニア', 'New Caledonia', -22.3, 166.5, 'Pacific/Noumea'),
  Country('WS', 'サモア', 'Samoa', -13.8, -171.8, 'Pacific/Apia'),
  Country('TO', 'トンガ', 'Tonga', -21.1, -175.2, 'Pacific/Tongatapu'),
  Country('KI', 'キリバス', 'Kiribati', 1.3, 173.0, 'Pacific/Tarawa'),
  Country('TV', 'ツバル', 'Tuvalu', -8.5, 179.2, 'Pacific/Funafuti'),
  Country('NR', 'ナウル', 'Nauru', -0.5, 166.9, 'Pacific/Nauru'),
  Country('MH', 'マーシャル諸島', 'Marshall Islands', 7.1, 171.4, 'Pacific/Majuro'),
  Country('FM', 'ミクロネシア連邦', 'Micronesia', 6.9, 158.2, 'Pacific/Pohnpei'),
  Country('PW', 'パラオ', 'Palau', 7.5, 134.6, 'Pacific/Palau'),
  Country('GU', 'グアム', 'Guam', 13.5, 144.8, 'Pacific/Guam'),
  Country(
    'PF',
    'フランス領ポリネシア',
    'French Polynesia',
    -17.5,
    -149.6,
    'Pacific/Tahiti',
  ),
];

/// ISO 3166-1 alpha-2コードから国を引く。不明なら`null`。
Country? countryByCode(String? code) {
  if (code == null) return null;
  for (final c in countries) {
    if (c.code == code) return c;
  }
  return null;
}
