import 'holiday_data.dart';

/// 宗教の識別子（設定に保存する）。
const kReligionChristian = 'christian';
const kReligionBuddhist = 'buddhist';
const kReligions = [kReligionChristian, kReligionBuddhist];

HolidayEntry _r(String id, String ja, String en, String fr) =>
    HolidayEntry(HolidayKind.religious, id, ja, en, fr);

/// [year]年のイースター（復活祭）。グレゴリオ暦の復活日の計算式（Computus）。
DateTime easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = (h + l - 7 * m + 114) % 31 + 1;
  return DateTime(year, month, day);
}

final Map<(int, int), HolidayEntry> _buddhistFixed = {
  (2, 15): _r('nehan', '涅槃会', 'Parinirvana Day', 'Parinirvana'),
  (4, 8): _r(
    'hanamatsuri',
    '花まつり',
    'Buddha’s Birthday',
    'Anniversaire du Bouddha',
  ),
  (12, 8): _r('jodo', '成道会', 'Bodhi Day', 'Jour de l’Éveil'),
};

/// [date]の宗教上の祝日のうち、[religions]で選ばれた宗教のもの。
List<HolidayEntry> religiousHolidaysOn(DateTime date, Set<String> religions) {
  final result = <HolidayEntry>[];
  final day = DateTime(date.year, date.month, date.day);
  if (religions.contains(kReligionChristian)) {
    if (date.month == 1 && date.day == 6) {
      result.add(_r('epiphany', '公現祭', 'Epiphany', 'Épiphanie'));
    }
    final easter = easterSunday(date.year);
    DateTime offset(int days) =>
        DateTime(easter.year, easter.month, easter.day + days);
    if (day == offset(-46)) {
      result.add(
        _r('ashWednesday', '灰の水曜日', 'Ash Wednesday', 'Mercredi des Cendres'),
      );
    }
    if (day == offset(-2)) {
      result.add(_r('goodFriday', '聖金曜日', 'Good Friday', 'Vendredi saint'));
    }
    if (day == easter) {
      result.add(_r('easter', 'イースター', 'Easter Sunday', 'Pâques'));
    }
    if (day == offset(39)) {
      result.add(_r('ascension', '昇天祭', 'Ascension Day', 'Ascension'));
    }
    if (day == offset(49)) {
      result.add(_r('pentecost', '聖霊降臨祭', 'Pentecost', 'Pentecôte'));
    }
  }
  if (religions.contains(kReligionBuddhist)) {
    final fixed = _buddhistFixed[(date.month, date.day)];
    if (fixed != null) result.add(fixed);
  }
  return result;
}
