import 'holiday_data.dart';

/// 世界共通の行事（祭日、2026-11-05追加）。休みではない。日付が固定のものと、
/// 第n日曜日で決まるものだけを収録する。国で扱いが違うもの（クリスマス・
/// ハロウィンなど）も、世界共通の行事として入れる。
HolidayEntry _o(String id, String ja, String en, String fr) =>
    HolidayEntry(HolidayKind.observance, id, ja, en, fr);

final Map<(int, int), HolidayEntry> _fixed = {
  (2, 3): _o('setsubun', '節分', 'Setsubun', 'Setsubun'),
  (2, 14): _o('valentine', 'バレンタインデー', 'Valentine’s Day', 'Saint-Valentin'),
  (3, 3): _o('hinamatsuri', 'ひな祭り', 'Hinamatsuri (Girls’ Day)', 'Hinamatsuri'),
  (3, 14): _o('whiteDay', 'ホワイトデー', 'White Day', 'White Day'),
  (7, 7): _o('tanabata', '七夕', 'Tanabata', 'Tanabata'),
  (10, 31): _o('halloween', 'ハロウィン', 'Halloween', 'Halloween'),
  (11, 15): _o('shichigosan', '七五三', 'Shichi-Go-San', 'Shichi-Go-San'),
  (12, 24): _o('christmasEve', 'クリスマスイブ', 'Christmas Eve', 'Veille de Noël'),
  (12, 25): _o('christmas', 'クリスマス', 'Christmas Day', 'Noël'),
  (12, 31): _o('newYearsEve', '大晦日', 'New Year’s Eve', 'Saint-Sylvestre'),
};

/// [date]の祭日（無ければ空）。
List<HolidayEntry> observancesOn(DateTime date) {
  final result = <HolidayEntry>[];
  final fixed = _fixed[(date.month, date.day)];
  if (fixed != null) result.add(fixed);
  final day = DateTime(date.year, date.month, date.day);
  if (day == nthWeekdayOfMonth(date.year, 5, DateTime.sunday, 2)) {
    result.add(_o('mothersDay', '母の日', 'Mother’s Day', 'Fête des mères'));
  }
  if (day == nthWeekdayOfMonth(date.year, 6, DateTime.sunday, 3)) {
    result.add(_o('fathersDay', '父の日', 'Father’s Day', 'Fête des pères'));
  }
  return result;
}
