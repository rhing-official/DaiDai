/// カレンダー（月表示・日程調整の候補日ピッカー）の週の始まりの曜日
/// （2026-10-04追加、ユーザー指示）。既定は日曜始まり（従来の固定挙動）。
enum CalendarWeekStart {
  sunday,
  monday;

  static CalendarWeekStart fromName(String? name) {
    return CalendarWeekStart.values.firstWhere(
      (start) => start.name == name,
      orElse: () => CalendarWeekStart.sunday,
    );
  }

  /// 月初[firstOfMonth]の前に並べる、前月の余白マス数（0〜6）。
  /// `DateTime.weekday`は月=1…日=7。
  int leadingBlanks(DateTime firstOfMonth) {
    return switch (this) {
      CalendarWeekStart.sunday => firstOfMonth.weekday % 7,
      CalendarWeekStart.monday => firstOfMonth.weekday - 1,
    };
  }

  /// 曜日ラベルの計算に使う、週の先頭にあたる日付（2023-01-01は日曜、
  /// 2023-01-02は月曜）。ここから7日分を並べれば週の並びになる。
  DateTime get weekdayLabelAnchor {
    return switch (this) {
      CalendarWeekStart.sunday => DateTime(2023, 1, 1),
      CalendarWeekStart.monday => DateTime(2023, 1, 2),
    };
  }
}
