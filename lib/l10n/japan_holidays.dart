import 'holiday_data.dart';

/// 日本の国民の祝日（2000〜2099年）を計算で求める（2026-11-05追加）。
///
/// 通信も外部パッケージも使わない（プライバシーファーストの方針）。春分・秋分は
/// 2000〜2099年に有効な近似式、ハッピーマンデー、振替休日、国民の休日、
/// 2019年・2020年・2021年の特例を含む。範囲外の年は祝日なしとして扱う。
enum JapanHoliday {
  newYear('元日', "New Year’s Day", 'Jour de l’An'),
  comingOfAge('成人の日', 'Coming of Age Day', 'Journée de la majorité'),
  foundation(
    '建国記念の日',
    'National Foundation Day',
    'Fête de la fondation nationale',
  ),
  emperorBirthday('天皇誕生日', 'Emperor’s Birthday', 'Anniversaire de l’empereur'),
  springEquinox('春分の日', 'Vernal Equinox Day', 'Équinoxe de printemps'),
  showa('昭和の日', 'Shōwa Day', 'Jour de Shōwa'),
  constitution('憲法記念日', 'Constitution Memorial Day', 'Jour de la Constitution'),
  greenery('みどりの日', 'Greenery Day', 'Jour de la verdure'),
  children('こどもの日', 'Children’s Day', 'Jour des enfants'),
  marine('海の日', 'Marine Day', 'Jour de la mer'),
  mountain('山の日', 'Mountain Day', 'Jour de la montagne'),
  respectForAged(
    '敬老の日',
    'Respect for the Aged Day',
    'Jour du respect des aînés',
  ),
  autumnEquinox('秋分の日', 'Autumnal Equinox Day', 'Équinoxe d’automne'),
  sports('スポーツの日', 'Sports Day', 'Jour du sport'),
  culture('文化の日', 'Culture Day', 'Jour de la culture'),
  laborThanksgiving(
    '勤労感謝の日',
    'Labour Thanksgiving Day',
    'Fête du travail et de la gratitude',
  ),
  substitute('休日(振替休日)', 'Substitute holiday', 'Jour férié compensatoire'),
  citizens('休日(国民の休日)', 'Citizens’ Holiday', 'Jour férié des citoyens'),
  enthronementEve(
    '休日(天皇の即位)',
    'Imperial accession holiday',
    'Jour de l’accession',
  ),
  enthronement('即位の日', 'Accession of the Emperor', 'Accession de l’empereur'),
  enthronementCeremony(
    '即位礼正殿の儀',
    'Ceremony of Enthronement',
    'Cérémonie d’intronisation',
  );

  const JapanHoliday(this.ja, this.en, this.fr);

  final String ja;
  final String en;
  final String fr;

  /// 表示言語（`ja`/`fr`/それ以外は英語）に応じた名称。
  String nameFor(String languageCode) {
    if (languageCode.startsWith('ja')) return ja;
    if (languageCode.startsWith('fr')) return fr;
    return en;
  }
}

final Map<int, Map<DateTime, JapanHoliday>> _cache = {};

DateTime _d(int y, int m, int d) => DateTime(y, m, d);

/// [year]年の第[n]月曜日。
DateTime _nthMonday(int year, int month, int n) {
  final first = DateTime(year, month);
  final offset = (DateTime.monday - first.weekday + 7) % 7;
  return DateTime(year, month, 1 + offset + (n - 1) * 7);
}

int _springEquinoxDay(int year) =>
    (20.69115 + 0.242194 * (year - 1980) - ((year - 1980) ~/ 4)).floor();

int _autumnEquinoxDay(int year) =>
    (23.09 + 0.242194 * (year - 1980) - ((year - 1980) ~/ 4)).floor();

Map<DateTime, JapanHoliday> _compute(int year) {
  final result = <DateTime, JapanHoliday>{};
  void put(DateTime date, JapanHoliday holiday) => result[date] = holiday;

  put(_d(year, 1, 1), JapanHoliday.newYear);
  put(_nthMonday(year, 1, 2), JapanHoliday.comingOfAge);
  put(_d(year, 2, 11), JapanHoliday.foundation);
  if (year >= 2020) put(_d(year, 2, 23), JapanHoliday.emperorBirthday);
  put(_d(year, 3, _springEquinoxDay(year)), JapanHoliday.springEquinox);
  put(_d(year, 4, 29), JapanHoliday.showa);
  put(_d(year, 5, 3), JapanHoliday.constitution);
  put(_d(year, 5, 4), JapanHoliday.greenery);
  put(_d(year, 5, 5), JapanHoliday.children);
  put(_nthMonday(year, 9, 3), JapanHoliday.respectForAged);
  put(_d(year, 9, _autumnEquinoxDay(year)), JapanHoliday.autumnEquinox);
  put(_d(year, 11, 3), JapanHoliday.culture);
  put(_d(year, 11, 23), JapanHoliday.laborThanksgiving);

  // 海の日・スポーツの日・山の日（東京オリンピックのため2020・2021年のみ移動）。
  switch (year) {
    case 2020:
      put(_d(2020, 7, 23), JapanHoliday.marine);
      put(_d(2020, 7, 24), JapanHoliday.sports);
      put(_d(2020, 8, 10), JapanHoliday.mountain);
    case 2021:
      put(_d(2021, 7, 22), JapanHoliday.marine);
      put(_d(2021, 7, 23), JapanHoliday.sports);
      put(_d(2021, 8, 8), JapanHoliday.mountain);
    default:
      put(_nthMonday(year, 7, 3), JapanHoliday.marine);
      put(_d(year, 8, 11), JapanHoliday.mountain);
      put(_nthMonday(year, 10, 2), JapanHoliday.sports);
  }

  // 2019年の特例（改元）。12/23の天皇誕生日は2019年に無い。
  if (year == 2019) {
    put(_d(2019, 4, 30), JapanHoliday.enthronementEve);
    put(_d(2019, 5, 1), JapanHoliday.enthronement);
    put(_d(2019, 5, 2), JapanHoliday.enthronementEve);
    put(_d(2019, 10, 22), JapanHoliday.enthronementCeremony);
  }

  // 国民の休日: 前日と翌日がどちらも祝日で、自身が日曜でも祝日でもない日。
  final dates = result.keys.toList()..sort();
  for (final date in dates) {
    final next = DateTime(date.year, date.month, date.day + 2);
    final between = DateTime(date.year, date.month, date.day + 1);
    if (result.containsKey(next) &&
        !result.containsKey(between) &&
        between.weekday != DateTime.sunday &&
        between.year == year) {
      put(between, JapanHoliday.citizens);
    }
  }

  // 振替休日: 日曜の祝日は、次の祝日でない日が休みになる。
  final sundays =
      result.keys.where((d) => d.weekday == DateTime.sunday).toList()..sort();
  for (final sunday in sundays) {
    var candidate = DateTime(sunday.year, sunday.month, sunday.day + 1);
    while (result.containsKey(candidate)) {
      candidate = DateTime(candidate.year, candidate.month, candidate.day + 1);
    }
    put(candidate, JapanHoliday.substitute);
  }
  return result;
}

/// [date]（暦日）が日本の祝日ならその種類、そうでなければnull。
JapanHoliday? japanHolidayOf(DateTime date) {
  final year = date.year;
  if (year < 2000 || year > 2099) return null;
  final holidays = _cache.putIfAbsent(year, () => _compute(year));
  return holidays[DateTime(date.year, date.month, date.day)];
}

/// [date]の日本の祝日を[HolidayEntry]（地域の祝日）として返す。祝日でなければnull。
HolidayEntry? japanHolidayEntryOf(DateTime date) {
  final holiday = japanHolidayOf(date);
  if (holiday == null) return null;
  return HolidayEntry(
    HolidayKind.public,
    'jp:${holiday.name}',
    holiday.ja,
    holiday.en,
    holiday.fr,
  );
}
