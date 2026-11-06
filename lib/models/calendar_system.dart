import 'package:intl/intl.dart';

/// カレンダーに表示する暦（2026-11-05追加）。予定のデータは常にグレゴリオ暦の
/// 日時で保存し、暦は**表示だけ**を変える。語らい毎の暦は自分の見え方にだけ効き、
/// 他の参加者の画面や予定のデータには影響しない。
enum CalendarSystem {
  gregorian,
  japanese;

  static CalendarSystem fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return CalendarSystem.gregorian;
  }

  static CalendarSystem? tryFromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

class _Era {
  const _Era(this.start, this.ja, this.en);
  final DateTime start;
  final String ja;
  final String en;
}

final _eras = [
  _Era(DateTime(2019, 5, 1), '令和', 'Reiwa'),
  _Era(DateTime(1989, 1, 8), '平成', 'Heisei'),
  _Era(DateTime(1926, 12, 25), '昭和', 'Showa'),
  _Era(DateTime(1912, 7, 30), '大正', 'Taisho'),
  // 明治6年（1873年）1月1日にグレゴリオ暦へ改暦。それ以前は太陰太陽暦なので扱わない。
  _Era(DateTime(1873, 1, 1), '明治', 'Meiji'),
];

/// [date]の元号表記（例: `令和8年`/`Reiwa 8`）。明治6年より前はnull。
({String ja, String en})? _eraYear(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  for (final era in _eras) {
    if (!day.isBefore(era.start)) {
      final year = day.year - era.start.year + 1;
      return (ja: '${era.ja}${year == 1 ? '元' : year}年', en: '${era.en} $year');
    }
  }
  return null;
}

/// 月の見出し（例: グレゴリオ暦=`2026年11月`、和暦=`令和8年11月`）。
String formatMonthTitle(
  CalendarSystem system,
  DateTime month,
  String localeCode,
) {
  if (system == CalendarSystem.japanese) {
    // 元号の切り替わりは月の途中なので、月の中ほどで判定する。
    final era = _eraYear(DateTime(month.year, month.month, 15));
    if (era != null) {
      if (localeCode.startsWith('ja')) {
        return '${era.ja}${DateFormat.MMMM(localeCode).format(month)}';
      }
      return '${DateFormat.MMMM(localeCode).format(month)} · ${era.en}';
    }
  }
  return DateFormat.yMMMM(localeCode).format(month);
}

/// 日付の見出し（例: グレゴリオ暦=`2026年11月5日(木)`、和暦=`令和8年11月5日(木)`）。
String formatDayTitle(CalendarSystem system, DateTime day, String localeCode) {
  if (system == CalendarSystem.japanese) {
    final era = _eraYear(day);
    if (era != null) {
      final monthDay = DateFormat.MMMEd(localeCode).format(day);
      if (localeCode.startsWith('ja')) return '${era.ja}$monthDay';
      return '$monthDay · ${era.en}';
    }
  }
  return DateFormat.yMMMEd(localeCode).format(day);
}
