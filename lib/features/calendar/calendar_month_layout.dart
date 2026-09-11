import '../../models/calendar_category.dart';
import '../../models/calendar_event.dart';
import '../../models/schedule_coordination.dart';

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// 月表示グリッドに描く「連続した1本の帯」1件分（2026-09-11追加）。
/// `CalendarEvent`は1件がそのまま1つの`CalendarMonthItem`になり、
/// `ScheduleCoordination`は連続した候補日のかたまりごとに分割される
/// （例: 候補日が9/11,9/12,9/13,9/20なら[9/11-9/13]と[9/20-9/20]の2件）。
class CalendarMonthItem {
  const CalendarMonthItem({
    required this.title,
    required this.categoryColor,
    required this.isCoordination,
    required this.startDate,
    required this.endDate,
    required this.event,
    required this.coordination,
  });

  final String title;

  /// カテゴリの色（0xRRGGBB）。カテゴリ未設定、または既に削除された
  /// categoryIdを参照している場合はnull（呼び出し側でアクセントカラー等へ
  /// フォールバックする）。
  final int? categoryColor;

  /// true=日程調整（未確定、点線描画に使う）、false=確定済み予定。
  final bool isCoordination;

  /// 両方とも暦日のみ・inclusive。
  final DateTime startDate;
  final DateTime endDate;

  /// タップ時の詳細ダイアログ表示用。[isCoordination]がfalseなら[event]、
  /// trueなら[coordination]が非null。
  final CalendarEvent? event;
  final ScheduleCoordination? coordination;
}

/// [events]/[coordinations]を、月表示で連続バーとして扱える
/// [CalendarMonthItem]の一覧に変換する。[categoriesById]は
/// `CalendarCategory.categoryId`をキーにした辞書（カテゴリ色の解決用）。
List<CalendarMonthItem> buildMonthItems(
  List<CalendarEvent> events,
  List<ScheduleCoordination> coordinations,
  Map<String, CalendarCategory> categoriesById,
) {
  final items = <CalendarMonthItem>[];

  for (final event in events) {
    final start = _dateOnly(event.startAt.toDate());
    final end = event.endAt != null ? _dateOnly(event.endAt!.toDate()) : start;
    items.add(
      CalendarMonthItem(
        title: event.title,
        categoryColor: categoriesById[event.categoryId]?.color,
        isCoordination: false,
        startDate: start,
        endDate: end,
        event: event,
        coordination: null,
      ),
    );
  }

  for (final coordination in coordinations) {
    final dates =
        coordination.candidateDates.map((ts) => _dateOnly(ts.toDate())).toList()
          ..sort();
    // 暦日が連続する区間ごとに分割する。
    var runStart = dates.isEmpty ? null : dates.first;
    var runEnd = runStart;
    for (var i = 1; i <= dates.length; i++) {
      final isLast = i == dates.length;
      final current = isLast ? null : dates[i];
      final isContiguous = !isLast && current!.difference(runEnd!).inDays == 1;
      if (isContiguous) {
        runEnd = current;
        continue;
      }
      items.add(
        CalendarMonthItem(
          title: coordination.title,
          categoryColor: categoriesById[coordination.categoryId]?.color,
          isCoordination: true,
          startDate: runStart!,
          endDate: runEnd!,
          event: null,
          coordination: coordination,
        ),
      );
      if (!isLast) {
        runStart = current;
        runEnd = current;
      }
    }
  }

  return items;
}

/// [computeWeekLaneLayout]が返す、週内に描画する1本の帯セグメント。
class WeekLaneSegment {
  const WeekLaneSegment({
    required this.item,
    required this.startCol,
    required this.endCol,
    required this.lane,
    required this.isTrueStart,
    required this.isTrueEnd,
  });

  final CalendarMonthItem item;

  /// この週内での列index（0=日曜〜6=土曜、`weekDays`の並びに従う）。
  final int startCol;
  final int endCol;

  /// この週の中での表示行（レーン、0始まり）。
  final int lane;

  /// この週内セグメントの開始/終了が、元の予定/日程調整の本当の開始/終了
  /// 日と一致するか。falseなら週をまたいだ継続のため、その側の角を丸めない。
  final bool isTrueStart;
  final bool isTrueEnd;
}

/// 1週間分の`CalendarMonthItem`を、レーン（表示行）へ貪欲法（区間グラフの
/// 彩色と同じロジック）で割り当てる。`maxLanes`を超える分は非表示にし、
/// 代わりに日ごとの非表示件数を返す（Googleカレンダーの「他N件」と同じ、
/// 日ごとに個別集計）。
class WeekLaneLayout {
  const WeekLaneLayout({
    required this.segments,
    required this.overflowCountByDay,
  });

  final List<WeekLaneSegment> segments;
  final Map<DateTime, int> overflowCountByDay;
}

WeekLaneLayout computeWeekLaneLayout(
  List<DateTime> weekDays,
  List<CalendarMonthItem> items,
  int maxLanes,
) {
  assert(weekDays.length == 7);
  final weekStart = weekDays.first;
  final weekEnd = weekDays.last;

  // 週の範囲にクリップした「週内セグメント」に変換する（週と重ならない
  // itemは除外）。
  final clipped = <({CalendarMonthItem item, int startCol, int endCol})>[];
  for (final item in items) {
    if (item.endDate.isBefore(weekStart) || item.startDate.isAfter(weekEnd)) {
      continue;
    }
    final clippedStart = item.startDate.isBefore(weekStart)
        ? weekStart
        : item.startDate;
    final clippedEnd = item.endDate.isAfter(weekEnd) ? weekEnd : item.endDate;
    clipped.add((
      item: item,
      startCol: clippedStart.difference(weekStart).inDays,
      endCol: clippedEnd.difference(weekStart).inDays,
    ));
  }

  // 開始列の昇順（同着なら長い帯を優先）でソートしてから貪欲法でレーンを
  // 割り当てる。
  clipped.sort((a, b) {
    final byStart = a.startCol.compareTo(b.startCol);
    if (byStart != 0) return byStart;
    return (b.endCol - b.startCol).compareTo(a.endCol - a.startCol);
  });

  final laneLastEndCol = <int>[]; // laneLastEndCol[lane] = そのレーンの最後のendCol
  final allSegments = <WeekLaneSegment>[];
  for (final entry in clipped) {
    var assignedLane = -1;
    for (var lane = 0; lane < laneLastEndCol.length; lane++) {
      if (laneLastEndCol[lane] < entry.startCol) {
        assignedLane = lane;
        break;
      }
    }
    if (assignedLane == -1) {
      assignedLane = laneLastEndCol.length;
      laneLastEndCol.add(entry.endCol);
    } else {
      laneLastEndCol[assignedLane] = entry.endCol;
    }
    allSegments.add(
      WeekLaneSegment(
        item: entry.item,
        startCol: entry.startCol,
        endCol: entry.endCol,
        lane: assignedLane,
        isTrueStart: entry.item.startDate == weekDays[entry.startCol],
        isTrueEnd: entry.item.endDate == weekDays[entry.endCol],
      ),
    );
  }

  final visibleSegments = <WeekLaneSegment>[];
  final overflowCountByDay = <DateTime, int>{
    for (final day in weekDays) day: 0,
  };
  for (final segment in allSegments) {
    if (segment.lane < maxLanes) {
      visibleSegments.add(segment);
    } else {
      for (var col = segment.startCol; col <= segment.endCol; col++) {
        final day = weekDays[col];
        overflowCountByDay[day] = (overflowCountByDay[day] ?? 0) + 1;
      }
    }
  }

  return WeekLaneLayout(
    segments: visibleSegments,
    overflowCountByDay: overflowCountByDay,
  );
}
