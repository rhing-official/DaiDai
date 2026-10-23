import '../l10n/app_locale.dart';
import '../models/profile_material.dart';

/// 誕生日の入力欄の項目。
enum BirthdayField { year, month, day }

/// 言語ごとの入力欄・表記の並び（2026-10-23追加）。日本語は年・月・日、
/// 英語（en-GB）・フランス語は日・月・年。
List<BirthdayField> birthdayFieldOrder(AppLocale locale) => switch (locale) {
  AppLocale.japanese => const [
    BirthdayField.year,
    BirthdayField.month,
    BirthdayField.day,
  ],
  AppLocale.britishEnglish || AppLocale.french => const [
    BirthdayField.day,
    BirthdayField.month,
    BirthdayField.year,
  ],
};

const _monthNamesEn = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _monthNamesFr = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// 月の表示名（入力欄の選択肢用）。日本語は「1月」。
String birthdayMonthLabel(int month, AppLocale locale) => switch (locale) {
  AppLocale.japanese => '$month月',
  AppLocale.britishEnglish => _monthNamesEn[month - 1],
  AppLocale.french => _monthNamesFr[month - 1],
};

/// 誕生日を[locale]の並びで整形する。日本語「2000年1月23日」「1月23日」、
/// 英語「23 January 2000」「23 January」、フランス語「23 janvier 2000」「23 janvier」。
/// カードを見る人の言語で整形する。
String formatBirthday(Birthday birthday, AppLocale locale) {
  final year = birthday.year;
  switch (locale) {
    case AppLocale.japanese:
      return '${year != null ? '$year年' : ''}${birthday.month}月${birthday.day}日';
    case AppLocale.britishEnglish:
    case AppLocale.french:
      final month = birthdayMonthLabel(birthday.month, locale);
      return '${birthday.day} $month${year != null ? ' $year' : ''}';
  }
}
