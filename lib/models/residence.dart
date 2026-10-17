import '../l10n/country_data.dart';
import '../l10n/prefecture_data.dart';

/// 住人の居住地（自己申告、2026-10-16追加）。伝書鳩の距離計算・現地時間、
/// 利用地域の把握（国単位）、将来の安否確認に使う。GPSは使わない。
/// `users/{uid}/private/residence`に保存し、本人以外は読めない。
class Residence {
  const Residence({
    required this.countryCode,
    this.prefectureCode,
    this.timeZone,
  });

  /// ISO 3166-1 alpha-2（必須）。
  final String countryCode;

  /// 日本の場合のみ。`JP-13`形式（任意）。
  final String? prefectureCode;

  /// 時差が複数ある国の場合のみ。IANA名（任意）。未入力なら国の既定を使う。
  final String? timeZone;

  Country? get country => countryByCode(countryCode);

  /// 距離計算に使う代表座標。都道府県があれば県庁所在地、無ければ国の首都。
  ({double lat, double lng})? get coordinates {
    final prefecture = prefectureByCode(prefectureCode);
    if (prefecture != null) return (lat: prefecture.lat, lng: prefecture.lng);
    final c = country;
    if (c == null) return null;
    return (lat: c.lat, lng: c.lng);
  }

  /// 現地時間の計算に使うタイムゾーン（IANA名）。
  String? get effectiveTimeZone => timeZone ?? country?.timeZone;

  factory Residence.fromJson(Map<String, dynamic> json) {
    return Residence(
      countryCode: json['countryCode'] as String,
      prefectureCode: json['prefectureCode'] as String?,
      timeZone: json['timeZone'] as String?,
    );
  }

  /// `updatedAt`はリポジトリがサーバー時刻で付ける。
  Map<String, dynamic> toJson() => {
    'countryCode': countryCode,
    if (prefectureCode != null) 'prefectureCode': prefectureCode,
    if (timeZone != null) 'timeZone': timeZone,
  };

  @override
  bool operator ==(Object other) =>
      other is Residence &&
      other.countryCode == countryCode &&
      other.prefectureCode == prefectureCode &&
      other.timeZone == timeZone;

  @override
  int get hashCode => Object.hash(countryCode, prefectureCode, timeZone);
}
