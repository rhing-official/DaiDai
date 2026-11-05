/// カレンダーに出す日の種類（2026-11-05追加）。Googleカレンダーと同じく、
/// 地域の祝日・世界共通の行事（祭日）・宗教上の祝日に分ける。
enum HolidayKind {
  /// 地域（国）の祝日。休みの日で、日付の数字も赤くする。
  public,

  /// 世界共通の行事（祭日）。休みではない。
  observance,

  /// 宗教上の祝日。休みではない。
  religious,
}

/// 祝日・祭日・宗教上の祝日1件分。名称は3言語を持つ。
class HolidayEntry {
  const HolidayEntry(this.kind, this.id, this.ja, this.en, this.fr);

  final HolidayKind kind;

  /// 種類の中で一意な識別子（テスト・重複判定用）。
  final String id;
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

/// [year]年の[month]月の第[n]日曜日（[weekday]は`DateTime.sunday`など）の日付。
DateTime nthWeekdayOfMonth(int year, int month, int weekday, int n) {
  final first = DateTime(year, month);
  final offset = (weekday - first.weekday + 7) % 7;
  return DateTime(year, month, 1 + offset + (n - 1) * 7);
}
