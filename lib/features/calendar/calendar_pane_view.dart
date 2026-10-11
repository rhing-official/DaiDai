import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/calendar_category.dart';
import '../../models/calendar_event.dart';
import '../../models/calendar_event_sync.dart';
import '../../models/calendar_week_start.dart';
import '../../models/schedule_coordination.dart';
import '../../providers/accent_color_provider.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/calendar_week_start_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/popup_surface_colors.dart';
import '../../widgets/glass/glass_app_bar.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/swipe_gestures.dart';
import 'calendar_add_choice_dialog.dart';
import 'calendar_category_list_popup.dart';
import 'calendar_event_detail_dialog.dart';
import 'calendar_event_form_dialog.dart';
import 'calendar_month_layout.dart';
import 'schedule_coordination_detail_dialog.dart';
import 'schedule_coordination_form_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// この幅未満ではモバイル向けの詰めたレイアウト（セル高さ・最大チップ表示数
/// 等を縮小）に切り替える。`home_screen.dart`/`talks_tab.dart`と同じく、
/// 画面ごとに専用のブレークポイント定数を持つ方式を踏襲する（2026-09-11追加）。
const _kCalendarMobileBreakpoint = 600.0;

/// 寄合単位の共有カレンダーを月表示で開く（2026-09-01追加）。
///
/// 当初は`Navigator.push`による全画面ルートとして実装したが、ワイド画面の
/// 分割表示（`TalksTab`）でフレンド/寄合一覧のサイドバーまで覆ってしまう
/// 不具合が発覚し、`DmChatPane`/`GroupChatPane`自身の表示領域（＝メッセージ
/// 画面の範囲）内に収まる差し替え表示に変更した（`EmbeddedCallPane`と同じ
/// 「ローカルなbool切り替えで中身を差し替える」方式、[onClose]呼び出し元が
/// その切り替えを担う）。Esc・上スクロール・下スワイプ・明示的な戻るボタンで
/// 閉じられる構成は、既存の添付ファイルフルスクリーンビューア
/// （`chat_screen.dart`の`_MediaViewerScreen`）と同じジェスチャー一式を
/// このファイル内で複製したもの（既存の動作済み機能を触らずに済ませるため、
/// 共通ウィジェットへの切り出しはあえて行っていない）。
class CalendarPaneView extends ConsumerStatefulWidget {
  const CalendarPaneView({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.currentUser,
    required this.onClose,
    super.key,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final AppUser currentUser;
  final VoidCallback onClose;

  @override
  ConsumerState<CalendarPaneView> createState() => _CalendarPaneViewState();
}

class _CalendarPaneViewState extends ConsumerState<CalendarPaneView> {
  late final Stream<List<CalendarEvent>> _eventsStream = ref
      .read(calendarEventRepositoryProvider)
      .watchEvents(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
      );

  late final Stream<List<ScheduleCoordination>> _coordinationsStream = ref
      .read(scheduleCoordinationRepositoryProvider)
      .watchCoordinations(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
      );

  late final Stream<List<CalendarCategory>> _categoriesStream = ref
      .read(calendarCategoryRepositoryProvider)
      .watchCategories(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
      );

  late DateTime _focusedMonth = _monthOf(DateTime.now());
  Timer? _scrollDismissTimer;

  static DateTime _monthOf(DateTime date) => DateTime(date.year, date.month);

  @override
  void dispose() {
    _scrollDismissTimer?.cancel();
    super.dispose();
  }

  /// 月送りのスライド方向（1=未来へ＝新しい月が右から入る、-1=過去へ、
  /// 2026-10-10追加）。[_setFocusedMonth]が移動先との前後関係で決める。
  int _slideDirection = 1;

  /// 表示する月を変える（setState内で呼ぶ）。移動先が今の月より前か後かで
  /// スライド方向を決める。
  void _setFocusedMonth(DateTime month) {
    final cmp = month.compareTo(_focusedMonth);
    if (cmp != 0) _slideDirection = cmp > 0 ? 1 : -1;
    _focusedMonth = month;
  }

  void _goToPreviousMonth() => setState(
    () =>
        _setFocusedMonth(DateTime(_focusedMonth.year, _focusedMonth.month - 1)),
  );

  void _goToNextMonth() => setState(
    () =>
        _setFocusedMonth(DateTime(_focusedMonth.year, _focusedMonth.month + 1)),
  );

  void _goToToday() =>
      setState(() => _setFocusedMonth(_monthOf(DateTime.now())));

  Future<void> _createEventOn(DateTime day) {
    final now = DateTime.now();
    return showCalendarEventFormDialog(
      context,
      isDm: widget.isDm,
      conversationId: widget.conversationId,
      roomId: widget.roomId,
      currentUserId: widget.currentUser.userId,
      currentUserRhingSeed: widget.currentUser.rhingSeed,
      initialDate: DateTime(day.year, day.month, day.day, now.hour, now.minute),
    );
  }

  Future<void> _createCoordinationOn(DateTime day) {
    return showScheduleCoordinationFormDialog(
      context,
      isDm: widget.isDm,
      conversationId: widget.conversationId,
      roomId: widget.roomId,
      currentUserId: widget.currentUser.userId,
      currentUserRhingSeed: widget.currentUser.rhingSeed,
      initialCandidateDate: day,
    );
  }

  /// 日付クリック/ポップアップの「＋」ボタンから呼ばれる、「予定追加/日程
  /// 調整」の選択（2026-09-05追加）。
  Future<void> _addOn(DateTime day) async {
    final choice = await showCalendarAddChoiceDialog(context);
    if (choice == null || !mounted) return;
    switch (choice) {
      case CalendarAddChoice.event:
        await _createEventOn(day);
      case CalendarAddChoice.scheduleCoordination:
        await _createCoordinationOn(day);
    }
  }

  /// 検索ボタンから開く、予定・日程調整のタイトル検索（2026-09-11追加）。
  /// `watchEvents`/`watchCoordinations`は寄合内の全期間を返す設計のため、
  /// 月をまたいだ検索が既に読み込み済みのデータだけで完結する。
  Future<void> _openCalendarSearch(
    List<CalendarEvent> events,
    List<ScheduleCoordination> coordinations,
  ) async {
    final strings = ref.read(appStringsProvider);
    final localeCode = ref.read(appLocaleProvider).languageCode;
    final result = await showDialog<_CalendarSearchSelection>(
      context: context,
      builder: (_) => _CalendarSearchDialog(
        events: events,
        coordinations: coordinations,
        strings: strings,
        localeCode: localeCode,
      ),
    );
    if (result == null || !mounted) return;
    switch (result) {
      case _CalendarSearchEventSelection(:final event):
        setState(() => _setFocusedMonth(_monthOf(event.startAt.toDate())));
        await showCalendarEventDetailDialog(
          context,
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          event: event,
          currentUser: widget.currentUser,
        );
      case _CalendarSearchCoordinationSelection(:final coordination):
        final firstCandidate = coordination.candidateDates.first.toDate();
        setState(() => _setFocusedMonth(_monthOf(firstCandidate)));
        await showScheduleCoordinationDetailDialog(
          context,
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          coordination: coordination,
          currentUser: widget.currentUser,
        );
    }
  }

  void _onDayTap(
    BuildContext cellContext,
    DateTime day,
    List<CalendarEvent> events,
    List<ScheduleCoordination> coordinations,
  ) {
    if (events.isEmpty && coordinations.isEmpty) {
      _addOn(day);
    } else {
      _showDayEventsPopup(cellContext, day, events, coordinations);
    }
  }

  /// タップした日付セルの直下に予定一覧を浮かべて表示する（2026-09-01、
  /// ボトムシートから変更。以前`_CalendarButton`が使っていたのと同じ
  /// `showMenu`＋`RelativeRect`方式、`album_popup_content.dart`と同じ
  /// パターン）。
  Future<void> _showDayEventsPopup(
    BuildContext cellContext,
    DateTime day,
    List<CalendarEvent> events,
    List<ScheduleCoordination> coordinations,
  ) async {
    final strings = ref.read(appStringsProvider);
    final localeCode = ref.read(appLocaleProvider).languageCode;
    final uiStyle = ref.read(appUiStyleProvider);

    final box = cellContext.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero);
    final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );

    await showMenu<void>(
      context: context,
      position: position,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _DayEventsPopupContent(
            day: day,
            events: events,
            coordinations: coordinations,
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            currentUserId: widget.currentUser.userId,
            uiStyle: uiStyle,
            strings: strings,
            localeCode: localeCode,
            onAdd: () {
              Navigator.of(context).pop();
              _addOn(day);
            },
            onOpenDetail: (event) {
              Navigator.of(context).pop();
              _openEventDetail(event);
            },
            onOpenCoordinationDetail: (coordination) {
              Navigator.of(context).pop();
              _openCoordinationDetail(coordination);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openEventDetail(CalendarEvent event) {
    return showCalendarEventDetailDialog(
      context,
      isDm: widget.isDm,
      conversationId: widget.conversationId,
      roomId: widget.roomId,
      event: event,
      currentUser: widget.currentUser,
    );
  }

  Future<void> _openCoordinationDetail(ScheduleCoordination coordination) {
    return showScheduleCoordinationDetailDialog(
      context,
      isDm: widget.isDm,
      conversationId: widget.conversationId,
      roomId: widget.roomId,
      coordination: coordination,
      currentUser: widget.currentUser,
    );
  }

  /// 月表示に重ねて描く連続バー（`_SpanBar`）をタップした際、Google
  /// Calendar本家と同じくその場でイベント/日程調整の詳細を直接開く
  /// （2026-09-11追加、日別一覧ポップアップとは別の導線）。
  void _openItemDetail(CalendarMonthItem item) {
    final event = item.event;
    if (event != null) {
      _openEventDetail(event);
      return;
    }
    final coordination = item.coordination;
    if (coordination != null) {
      _openCoordinationDetail(coordination);
    }
  }

  /// 設定（歯車）ボタン直下にカテゴリ管理をドロップダウン形式で開く
  /// （2026-09-11、中央寄せDialogから変更）。`_showDayEventsPopup`と同じ
  /// `showMenu`＋`RelativeRect`方式で、ボタン自身の`BuildContext`
  /// （`_MonthHeader`内の`Builder`から渡される）から位置を計算する。
  Future<void> _openCategoryManagement(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero);
    final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );

    await showMenu<void>(
      context: context,
      position: position,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: CalendarCategoryListPopup(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final localeCode = ref.watch(appLocaleProvider).languageCode;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGlass = uiStyle == AppUiStyle.glass;
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final accent = ref.watch(accentColorProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile =
        MediaQuery.sizeOf(context).width < _kCalendarMobileBreakpoint;

    final leadingButton = IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: '',
      onPressed: widget.onClose,
    );
    final title = Text(strings.calendarFullScreenTitle);

    return Scaffold(
      appBar: isGlass
          ? GlassAppBar(leading: leadingButton, title: title)
          : AppBar(leading: leadingButton, title: title),
      // Esc・上スクロール（PC）・下スワイプ（モバイル）でメッセージ画面に戻る。
      // `_MediaViewerScreen`と同じ3系統の仕組みをここでも組み合わせる。左右
      // 矢印キー・横スワイプでの月送りもここに追加する（2026-09-01）。
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onClose();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _goToPreviousMonth();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _goToNextMonth();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && event.scrollDelta.dy < -2.0) {
              _scrollDismissTimer?.cancel();
              _scrollDismissTimer = Timer(
                const Duration(milliseconds: 150),
                () {
                  if (mounted) widget.onClose();
                },
              );
            }
          },
          // 1つのGestureDetectorにonHorizontalDragXxxとonVerticalDragXxxを
          // 同時に設定するとFlutterが例外を投げるため、下スワイプ＝閉じる
          // （SwipeDownToDismiss、縦方向）とは別のGestureDetectorを重ねて
          // 横スワイプ＝月送りを処理する。
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity >= kSwipeGestureVelocityThreshold) {
                _goToPreviousMonth();
              } else if (velocity <= -kSwipeGestureVelocityThreshold) {
                _goToNextMonth();
              }
            },
            child: SwipeDownToDismiss(
              onDismiss: widget.onClose,
              // 月全体をスクロール無しで1画面に収める（2026-10-07、ユーザー指示。
              // Googleカレンダー同様）。週の高さは利用可能な高さから決まり
              // （`_MonthGrid`）、収まっている間は縦スクロールが発生しないため
              // 下スワイプ（`SwipeDownToDismiss`）が効く。極端に低い画面だけは
              // 最小行高を保つためスクロールにフォールバックする。モバイルは
              // 横いっぱいに広げる（水平パディング0）。
              child: LayoutBuilder(
                builder: (context, viewport) {
                  final padding = isMobile
                      ? const EdgeInsets.symmetric(vertical: 8)
                      : const EdgeInsets.all(16);
                  final weekCount = _weekCountOf(
                    _focusedMonth,
                    ref.watch(calendarWeekStartProvider),
                  );
                  final contentHeight = math.max(
                    viewport.maxHeight - padding.vertical,
                    _kMonthChromeHeight + weekCount * _rowHeightFor(1),
                  );
                  return SingleChildScrollView(
                    padding: padding,
                    child: SizedBox(
                      height: contentHeight,
                      child: StreamBuilder<List<CalendarEvent>>(
                        stream: _eventsStream,
                        builder: (context, eventsSnapshot) {
                          final events =
                              eventsSnapshot.data ?? const <CalendarEvent>[];
                          final eventsByDate =
                              <DateTime, List<CalendarEvent>>{};
                          for (final event in events) {
                            // 複数日にまたがる予定は、対象日全てにマークを付ける
                            // （2026-09-04修正、以前は開始日にしか登録していなかった）。
                            for (final day in calendarEventDates(event)) {
                              (eventsByDate[day] ??= []).add(event);
                            }
                          }
                          return StreamBuilder<List<ScheduleCoordination>>(
                            stream: _coordinationsStream,
                            builder: (context, coordinationsSnapshot) {
                              // 月表示に印を付けるのは未確定のものだけ（確定済みは
                              // 実際の予定として既にeventsByDateに現れる、
                              // 2026-09-05追加）。
                              final coordinations =
                                  (coordinationsSnapshot.data ??
                                          const <ScheduleCoordination>[])
                                      .where((c) => !c.isFinalized)
                                      .toList();
                              final coordinationsByDate =
                                  <DateTime, List<ScheduleCoordination>>{};
                              for (final coordination in coordinations) {
                                for (final ts in coordination.candidateDates) {
                                  final day = _dateOnly(ts.toDate());
                                  (coordinationsByDate[day] ??= []).add(
                                    coordination,
                                  );
                                }
                              }
                              return StreamBuilder<List<CalendarCategory>>(
                                stream: _categoriesStream,
                                builder: (context, categoriesSnapshot) {
                                  final categories =
                                      categoriesSnapshot.data ??
                                      const <CalendarCategory>[];
                                  final categoriesById = {
                                    for (final category in categories)
                                      category.categoryId: category,
                                  };
                                  final monthItems = buildMonthItems(
                                    events,
                                    coordinations,
                                    categoriesById,
                                  );
                                  return Column(
                                    children: [
                                      _MonthHeader(
                                        month: _focusedMonth,
                                        localeCode: localeCode,
                                        todayLabel: strings.calendarTodayButton,
                                        searchTooltip:
                                            strings.calendarSearchTooltip,
                                        categorySettingsTooltip: strings
                                            .calendarCategorySettingsTooltip,
                                        onPrevious: _goToPreviousMonth,
                                        onNext: _goToNextMonth,
                                        onToday: _goToToday,
                                        onSearch: () => _openCalendarSearch(
                                          events,
                                          coordinations,
                                        ),
                                        onManageCategories:
                                            _openCategoryManagement,
                                      ),
                                      const SizedBox(height: 8),
                                      _WeekdayHeaderRow(
                                        localeCode: localeCode,
                                        gridLineColor: colorScheme.outline,
                                      ),
                                      Expanded(
                                        // 月送りは、新しい月が移動方向から
                                        // スライドして入り、前の月が反対側へ
                                        // 出ていく（2026-10-10追加）。
                                        child: _MonthSlideSwitcher(
                                          month: _focusedMonth,
                                          direction: _slideDirection,
                                          child: _MonthGrid(
                                            key: ValueKey(_focusedMonth),
                                            focusedMonth: _focusedMonth,
                                            monthItems: monthItems,
                                            isGekiga: isGekiga,
                                            isMobile: isMobile,
                                            accentColor: accent,
                                            colorScheme: colorScheme,
                                            strings: strings,
                                            onDayTap: (cellContext, day) =>
                                                _onDayTap(
                                                  cellContext,
                                                  day,
                                                  eventsByDate[day] ?? const [],
                                                  coordinationsByDate[day] ??
                                                      const [],
                                                ),
                                            onItemTap: _openItemDetail,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.localeCode,
    required this.todayLabel,
    required this.searchTooltip,
    required this.categorySettingsTooltip,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onSearch,
    required this.onManageCategories,
  });

  final DateTime month;
  final String localeCode;
  final String todayLabel;
  final String searchTooltip;
  final String categorySettingsTooltip;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onSearch;
  final void Function(BuildContext buttonContext) onManageCategories;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: '',
          onPressed: onPrevious,
        ),
        Expanded(
          child: Text(
            DateFormat.yMMMM(localeCode).format(month),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: '',
          onPressed: onNext,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextButton(onPressed: onToday, child: Text(todayLabel)),
        ),
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: searchTooltip,
          onPressed: onSearch,
        ),
        Builder(
          builder: (buttonContext) => IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: categorySettingsTooltip,
            onPressed: () => onManageCategories(buttonContext),
          ),
        ),
      ],
    );
  }
}

class _WeekdayHeaderRow extends ConsumerWidget {
  const _WeekdayHeaderRow({
    required this.localeCode,
    required this.gridLineColor,
  });

  final String localeCode;
  final Color gridLineColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 週の先頭の曜日（日曜/月曜、設定）から7日分の曜日ラベル（最短表記）を作る。
    final anchor = ref.watch(calendarWeekStartProvider).weekdayLabelAnchor;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: gridLineColor)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(
                  DateFormat.EEEEE(
                    localeCode,
                  ).format(anchor.add(Duration(days: i))),
                  style: labelStyle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 月表示グリッドのレイアウト定数（`_MonthGrid`/`_WeekRow`/`_DayCellBackground`
// 間で共有、2026-09-11追加）。行の高さはこれらから逆算するため、値を変える
// 場合はここだけ直せばよい。
const _kCellPadding = 4.0;
const _kDayNumberAreaHeight = 26.0;
const _kLaneHeight = 24.0;
const _kLaneGap = 3.0;
const _kOverflowRowHeight = 18.0;

double _rowHeightFor(int maxLanes) =>
    _kCellPadding * 2 +
    _kDayNumberAreaHeight +
    maxLanes * (_kLaneHeight + _kLaneGap) +
    _kOverflowRowHeight;

/// 月ヘッダー（アイコンボタン48＋余白8）と曜日行（約22）の合計高さの目安。
/// 月全体を1画面に収められるか（スクロールへフォールバックするか）の判定用。
const _kMonthChromeHeight = 80.0;

int _weekCountOf(DateTime month, CalendarWeekStart weekStart) {
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final leading = weekStart.leadingBlanks(DateTime(month.year, month.month));
  return ((leading + daysInMonth) / 7).ceil();
}

double _laneTop(int lane) =>
    _kCellPadding + _kDayNumberAreaHeight + lane * (_kLaneHeight + _kLaneGap);

/// 月グリッドの切り替えを、移動方向へのスライドで見せる（2026-10-10追加）。
/// [direction]が1なら新しい月は右から入り前の月は左へ出る（-1なら逆）。
/// 子には月ごとの`ValueKey`を付けること。
class _MonthSlideSwitcher extends StatelessWidget {
  const _MonthSlideSwitcher({
    required this.month,
    required this.direction,
    required this.child,
  });

  final DateTime month;
  final int direction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          fit: StackFit.expand,
          children: [...previousChildren, ?currentChild],
        ),
        transitionBuilder: (child, animation) {
          final entering = child.key == ValueKey(month);
          // 入る側: 移動方向の端から中央へ。出る側（逆再生）: 中央から反対側へ。
          final begin = Offset(
            entering ? direction.toDouble() : -direction.toDouble(),
            0,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: begin,
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
        child: child,
      ),
    );
  }
}

class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({
    super.key,
    required this.focusedMonth,
    required this.monthItems,
    required this.isGekiga,
    required this.isMobile,
    required this.accentColor,
    required this.colorScheme,
    required this.strings,
    required this.onDayTap,
    required this.onItemTap,
  });

  final DateTime focusedMonth;
  final List<CalendarMonthItem> monthItems;
  final bool isGekiga;
  final bool isMobile;
  final Color accentColor;
  final ColorScheme colorScheme;
  final Strings strings;
  final void Function(BuildContext cellContext, DateTime day) onDayTap;
  final void Function(CalendarMonthItem item) onItemTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = focusedMonth.year;
    final month = focusedMonth.month;
    final firstOfMonth = DateTime(year, month);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // 週の始まり（日曜/月曜、設定）に応じた先頭余白マス数。
    final leadingBlanks = ref
        .watch(calendarWeekStartProvider)
        .leadingBlanks(firstOfMonth);
    final totalCells = leadingBlanks + daysInMonth;
    final trailingBlanks = (7 - totalCells % 7) % 7;

    final cells = <DateTime>[
      for (var i = leadingBlanks; i > 0; i--)
        firstOfMonth.subtract(Duration(days: i)),
      for (var d = 1; d <= daysInMonth; d++) DateTime(year, month, d),
      for (var i = 1; i <= trailingBlanks; i++)
        DateTime(year, month, daysInMonth).add(Duration(days: i)),
    ];

    final today = _dateOnly(DateTime.now());
    final weeks = <List<DateTime>>[
      for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
    ];

    // 利用可能な高さを週数で等分し（最小は1レーン分）、その行高に収まる
    // レーン数だけ予定の帯を表示する（残りは「他N件」、2026-10-07変更。
    // 以前は端末幅で固定の2/3レーンと固定の行高だったため、画面高を超えて
    // スクロールが必要になっていた）。
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.hasBoundedHeight
            ? constraints.maxHeight / weeks.length
            : _rowHeightFor(isMobile ? 2 : 3);
        final rowHeight = math.max(_rowHeightFor(1), available);
        final maxLanes =
            ((rowHeight - _rowHeightFor(0)) / (_kLaneHeight + _kLaneGap))
                .floor()
                .clamp(1, 6);
        return Column(
          children: [
            for (final week in weeks)
              _WeekRow(
                weekDays: week,
                month: month,
                today: today,
                monthItems: monthItems,
                maxLanes: maxLanes,
                rowHeight: rowHeight,
                isGekiga: isGekiga,
                accentColor: accentColor,
                colorScheme: colorScheme,
                strings: strings,
                onDayTap: onDayTap,
                onItemTap: onItemTap,
              ),
          ],
        );
      },
    );
  }
}

/// 1週間分の行。背景（グリッド線・日番号・今日の丸・他N件）を`Row`で描き、
/// その上に`computeWeekLaneLayout`が割り当てたレーンを`Positioned`で重ねて
/// 連続バーを描く2層構成（2026-09-11追加、Googleカレンダー月表示の
/// 「複数日イベントが横に連なった1本の帯になる」挙動を再現するため）。
class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.weekDays,
    required this.month,
    required this.today,
    required this.monthItems,
    required this.maxLanes,
    required this.rowHeight,
    required this.isGekiga,
    required this.accentColor,
    required this.colorScheme,
    required this.strings,
    required this.onDayTap,
    required this.onItemTap,
  });

  final List<DateTime> weekDays;
  final int month;
  final DateTime today;
  final List<CalendarMonthItem> monthItems;
  final int maxLanes;
  final double rowHeight;
  final bool isGekiga;
  final Color accentColor;
  final ColorScheme colorScheme;
  final Strings strings;
  final void Function(BuildContext cellContext, DateTime day) onDayTap;
  final void Function(CalendarMonthItem item) onItemTap;

  @override
  Widget build(BuildContext context) {
    final layout = computeWeekLaneLayout(weekDays, monthItems, maxLanes);

    return SizedBox(
      height: rowHeight,
      child: Stack(
        children: [
          Row(
            children: [
              for (final day in weekDays)
                Expanded(
                  child: _DayCellBackground(
                    day: day,
                    isCurrentMonth: day.month == month,
                    isToday: day == today,
                    overflowCount: layout.overflowCountByDay[day] ?? 0,
                    isGekiga: isGekiga,
                    accentColor: accentColor,
                    colorScheme: colorScheme,
                    strings: strings,
                    onTap: day.month == month
                        ? (cellContext) => onDayTap(cellContext, day)
                        : null,
                  ),
                ),
            ],
          ),
          // バーの無い領域はStackの空白部分としてタップを素通りさせ、下の
          // 背景レイヤー（セルのInkWell）に届く（2026-09-11）。
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columnWidth = constraints.maxWidth / 7;
                return Stack(
                  children: [
                    for (final segment in layout.segments)
                      Positioned(
                        left: segment.startCol * columnWidth + _kCellPadding,
                        width:
                            (segment.endCol - segment.startCol + 1) *
                                columnWidth -
                            _kCellPadding * 2,
                        top: _laneTop(segment.lane),
                        height: _kLaneHeight,
                        child: _SpanBar(
                          segment: segment,
                          isGekiga: isGekiga,
                          accentColor: accentColor,
                          onTap: () => onItemTap(segment.item),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 週の行の背景レイヤー1マス分。日付ごとの区切り線（グリッド線）・日番号
/// （中央揃え）・今日の白抜き丸・「他N件」のみを描く。予定/日程調整本体は
/// `_WeekRow`が前景レイヤーの`_SpanBar`として重ねて描く（2026-09-11、
/// 以前はこのセル自身がチップを積んでいたが、日をまたぐ連続バーを表現する
/// ため前景レイヤーに分離した）。
class _DayCellBackground extends StatelessWidget {
  const _DayCellBackground({
    required this.day,
    required this.isCurrentMonth,
    required this.isToday,
    required this.overflowCount,
    required this.isGekiga,
    required this.accentColor,
    required this.colorScheme,
    required this.strings,
    required this.onTap,
  });

  final DateTime day;
  final bool isCurrentMonth;
  final bool isToday;
  final int overflowCount;
  final bool isGekiga;
  final Color accentColor;
  final ColorScheme colorScheme;
  final Strings strings;

  /// タップしたセル自身の`BuildContext`（`Padding`のRenderBox）を渡す
  /// （2026-09-01追加。予定一覧ポップアップの位置決めに使うため）。
  final void Function(BuildContext cellContext)? onTap;

  @override
  Widget build(BuildContext context) {
    final dayNumber = isToday
        ? Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // 「今日」は塗りつぶさない輪郭のみの丸（白抜き）で示す
              // （2026-09-11、以前実装した塗りつぶし円から差し戻し）。
              border: Border.all(
                color: isGekiga ? colorScheme.onSurface : accentColor,
                width: 1.5,
              ),
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
              // フォントの行送り（アセント/ディセント）を打ち消し、丸の
              // 幾何中心と数字の見た目の中心を一致させる（2026-09-12）。
              strutStyle: const StrutStyle(
                fontSize: 14,
                height: 1,
                forceStrutHeight: true,
              ),
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
            ),
          )
        : Text(
            '${day.day}',
            style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
          );

    return Opacity(
      // 当月以外の日はセル全体を薄く表示する（2026-09-11、個々の色計算では
      // なくセル全体をOpacityで包むことで前景バーにも一律適用させる）。
      opacity: isCurrentMonth ? 1 : 0.35,
      child: DecoratedBox(
        // 日付ごとの区切り線（グリッド線）。全セルに同じ枠線を付けるだけで
        // 隣接セル同士が線を共有し格子状になる（2026-09-11追加）。
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outline, width: 0.5),
        ),
        child: InkWell(
          onTap: onTap == null ? null : () => onTap!(context),
          child: Padding(
            padding: const EdgeInsets.all(_kCellPadding),
            child: Column(
              // Google本家同様、日番号は中央揃えにする（2026-09-11、以前は
              // 左詰めだった）。
              children: [
                SizedBox(
                  height: _kDayNumberAreaHeight - _kCellPadding,
                  child: Center(child: dayNumber),
                ),
                const Spacer(),
                if (overflowCount > 0)
                  Text(
                    strings.calendarMoreEventsLabel(overflowCount),
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 日をまたいで連続する予定/日程調整を表す帯1本分（2026-09-11追加、以前の
/// セル内チップ`_EventChip`/`_CoordinationChip`を置き換える）。同じ週内では
/// 列をまたいで幅を広げるが、週をまたいだ継続の視覚的な繋がりは表現せず、
/// 週ごとのセグメントを常に独立した完全な角丸ブロックとして描画する。
/// Google Calendar本家と同じく単体タップでその予定/日程調整の詳細を直接開く。
class _SpanBar extends StatelessWidget {
  const _SpanBar({
    required this.segment,
    required this.isGekiga,
    required this.accentColor,
    required this.onTap,
  });

  final WeekLaneSegment segment;
  final bool isGekiga;
  final Color accentColor;
  final VoidCallback onTap;

  static const _cornerRadius = Radius.circular(4);

  @override
  Widget build(BuildContext context) {
    final item = segment.item;
    final borderRadius = BorderRadius.all(_cornerRadius);

    // 予定・日程調整とも共通で、種類（カテゴリ）に設定した色を塗る。未設定
    // ならアクセントカラーで塗る。劇画は色の概念を持たないため常に黒地に
    // 統一する（CLAUDE.md「劇画は常にモノクロ」方針、2026-09-11更新: 以前は
    // 輪郭のみだったが、ユーザー指示で塗りつぶしに変更した）。日程調整も
    // 予定と全く同じ見た目（枠線無し、塗りのみ）に統一する（2026-09-11、
    // 以前付けていた実線の縁取りも撤回）。
    final fillColor = isGekiga
        ? Colors.black
        : Color(
            0xFF000000 |
                (item.categoryColor ?? (accentColor.toARGB32() & 0xFFFFFF)),
          );
    // フォント色は塗り色に対する明度コントラストで黒/白を選ぶ（2026-09-11、
    // 「種類設定時はアクセントカラー」の指示を撤回し、外観の色と反対の色に
    // 統一）。劇画は白固定。
    final textColor = isGekiga ? Colors.white : _onColorFor(fillColor);

    final title = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: textColor),
      ),
    );

    final bar = DecoratedBox(
      decoration: BoxDecoration(color: fillColor, borderRadius: borderRadius),
      child: title,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: bar,
    );
  }
}

/// 背景色の明度から、読みやすい文字色（黒/白）を選ぶ。カテゴリ色は住人が
/// 自由入力するため、テーマのライト/ダーク固定ではなく色自体の明度から
/// 判定する必要がある（2026-09-11追加）。
Color _onColorFor(Color background) =>
    background.computeLuminance() > 0.5 ? Colors.black : Colors.white;

/// 検索ダイアログのタップ結果（2026-09-11追加）。予定/日程調整のどちらを
/// 選んだかで、呼び出し元（`_CalendarPaneViewState._openCalendarSearch`）が
/// 開く詳細ダイアログを出し分ける。
sealed class _CalendarSearchSelection {
  const _CalendarSearchSelection();
}

class _CalendarSearchEventSelection extends _CalendarSearchSelection {
  const _CalendarSearchEventSelection(this.event);
  final CalendarEvent event;
}

class _CalendarSearchCoordinationSelection extends _CalendarSearchSelection {
  const _CalendarSearchCoordinationSelection(this.coordination);
  final ScheduleCoordination coordination;
}

/// 検索ボタンから開く、タイトルの部分一致検索ダイアログ（2026-09-11追加）。
/// `watchEvents`/`watchCoordinations`が寄合内の全期間を返す設計のため、
/// 既に読み込み済みの[events]/[coordinations]をクライアント側でフィルタする
/// だけで、月をまたいだ検索が成立する。
class _CalendarSearchDialog extends StatefulWidget {
  const _CalendarSearchDialog({
    required this.events,
    required this.coordinations,
    required this.strings,
    required this.localeCode,
  });

  final List<CalendarEvent> events;
  final List<ScheduleCoordination> coordinations;
  final Strings strings;
  final String localeCode;

  @override
  State<_CalendarSearchDialog> createState() => _CalendarSearchDialogState();
}

class _CalendarSearchDialogState extends State<_CalendarSearchDialog> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final hasQuery = query.isNotEmpty;
    final matchingEvents = hasQuery
        ? widget.events
              .where((event) => event.title.toLowerCase().contains(query))
              .toList()
        : const <CalendarEvent>[];
    final matchingCoordinations = hasQuery
        ? widget.coordinations
              .where(
                (coordination) =>
                    coordination.title.toLowerCase().contains(query),
              )
              .toList()
        : const <ScheduleCoordination>[];
    final hasResults =
        matchingEvents.isNotEmpty || matchingCoordinations.isNotEmpty;
    final dateFormat = DateFormat.yMMMEd(widget.localeCode);

    return KeyboardAlertDialog(
      title: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.strings.calendarSearchHint,
          prefixIcon: const Icon(Icons.search),
        ),
        onChanged: (value) => setState(() => _query = value),
      ),
      content: SizedBox(
        width: 360,
        child: !hasQuery
            ? const SizedBox.shrink()
            : !hasResults
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(widget.strings.calendarSearchEmptyLabel),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final event in matchingEvents)
                      ListTile(
                        title: Text(event.title),
                        subtitle: Text(
                          dateFormat.format(event.startAt.toDate()),
                        ),
                        onTap: () => Navigator.of(
                          context,
                        ).pop(_CalendarSearchEventSelection(event)),
                      ),
                    for (final coordination in matchingCoordinations)
                      ListTile(
                        title: Text(coordination.title),
                        subtitle: Text(
                          dateFormat.format(
                            coordination.candidateDates.first.toDate(),
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(
                          _CalendarSearchCoordinationSelection(coordination),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.strings.cancel),
        ),
      ],
    );
  }
}

/// タップした日付セルの直下に浮かべるポップアップの中身。`showMenu`は
/// `color: Colors.transparent`で呼んでいるため、この中でカード自体の
/// 背景・枠線を持つ必要がある（`popup_surface_colors.dart`、
/// `album_popup_content.dart`と同じパターン）。
class _DayEventsPopupContent extends StatelessWidget {
  const _DayEventsPopupContent({
    required this.day,
    required this.events,
    required this.coordinations,
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.currentUserId,
    required this.uiStyle,
    required this.strings,
    required this.localeCode,
    required this.onAdd,
    required this.onOpenDetail,
    required this.onOpenCoordinationDetail,
  });

  final DateTime day;
  final List<CalendarEvent> events;
  final List<ScheduleCoordination> coordinations;
  final bool isDm;
  final String conversationId;
  final String roomId;
  final String currentUserId;
  final AppUiStyle uiStyle;
  final Strings strings;
  final String localeCode;
  final VoidCallback onAdd;
  final void Function(CalendarEvent event) onOpenDetail;
  final void Function(ScheduleCoordination coordination)
  onOpenCoordinationDetail;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final onInverse = popupCardForeground(brightness, uiStyle);
    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat.yMMMEd(localeCode).format(day),
                  style: TextStyle(
                    color: onInverse,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.add, size: 20, color: onInverse),
                tooltip: '',
                onPressed: onAdd,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _DayEventCard(
                isDm: isDm,
                conversationId: conversationId,
                roomId: roomId,
                currentUserId: currentUserId,
                event: event,
                uiStyle: uiStyle,
                strings: strings,
                localeCode: localeCode,
                onTap: () => onOpenDetail(event),
              ),
            ),
          for (final coordination in coordinations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _DayCoordinationCard(
                coordination: coordination,
                uiStyle: uiStyle,
                strings: strings,
                onTap: () => onOpenCoordinationDetail(coordination),
              ),
            ),
        ],
      ),
    );

    return SizedBox(
      width: 300,
      child: Container(
        decoration: BoxDecoration(
          color: popupCardBackground(brightness, uiStyle),
          border: Border.all(color: popupCardBorder(brightness, uiStyle)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: content,
      ),
    );
  }
}

/// 予定1件分のカード。旧`calendar_popup_content.dart`の
/// `_CalendarEventPopupCard`と同じ、`popup_surface_colors.dart`の
/// 反転配色を使うポップアップ専用カード。
class _DayEventCard extends ConsumerWidget {
  const _DayEventCard({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.currentUserId,
    required this.event,
    required this.uiStyle,
    required this.strings,
    required this.localeCode,
    required this.onTap,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final String currentUserId;
  final CalendarEvent event;
  final AppUiStyle uiStyle;
  final Strings strings;
  final String localeCode;
  final VoidCallback onTap;

  String? _syncStatusLabel(CalendarSyncStatus? status) {
    switch (status) {
      case CalendarSyncStatus.synced:
        return strings.calendarSyncStatusSyncedLabel;
      case CalendarSyncStatus.failed:
        return strings.calendarSyncStatusFailedLabel;
      case CalendarSyncStatus.skipped:
        return strings.calendarSyncStatusSkippedLabel;
      case CalendarSyncStatus.pending:
      case CalendarSyncStatus.syncing:
        return strings.calendarSyncStatusPendingLabel;
      case CalendarSyncStatus.pendingDelete:
      case CalendarSyncStatus.deleting:
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGlass = uiStyle == AppUiStyle.glass;
    final timeFormat = DateFormat.Hm(localeCode);
    final timeLabel = event.isAllDay
        ? strings.calendarAllDayLabel
        : (event.endAt != null
              ? '${timeFormat.format(event.startAt.toDate())} - ${timeFormat.format(event.endAt!.toDate())}'
              : timeFormat.format(event.startAt.toDate()));

    final syncState = ref
        .watch(
          _syncStateProvider((
            isDm: isDm,
            conversationId: conversationId,
            roomId: roomId,
            eventId: event.eventId,
            uid: currentUserId,
          )),
        )
        .asData
        ?.value;
    final syncLabel = _syncStatusLabel(syncState?.status);
    final brightness = Theme.of(context).brightness;
    final onInverse = popupCardForeground(brightness, uiStyle);

    final body = Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            event.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: onInverse, fontWeight: FontWeight.w600),
          ),
          Text(
            timeLabel,
            style: TextStyle(
              color: onInverse.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          if (event.location != null && event.location!.isNotEmpty)
            Text(
              event.location!,
              style: TextStyle(
                color: onInverse.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          if (syncLabel != null)
            Text(
              syncLabel,
              style: TextStyle(
                color: onInverse.withValues(alpha: 0.55),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );

    return isGlass
        ? GlassSurface(
            variant: GlassVariant.card,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: body,
            ),
          )
        : Material(
            color: onInverse.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: body,
            ),
          );
  }
}

/// 日程調整1件分のカード（2026-09-05追加）。`_DayEventCard`と同じ
/// `popup_surface_colors.dart`の反転配色を使うポップアップ専用カード。
class _DayCoordinationCard extends StatelessWidget {
  const _DayCoordinationCard({
    required this.coordination,
    required this.uiStyle,
    required this.strings,
    required this.onTap,
  });

  final ScheduleCoordination coordination;
  final AppUiStyle uiStyle;
  final Strings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isGlass = uiStyle == AppUiStyle.glass;
    final brightness = Theme.of(context).brightness;
    final onInverse = popupCardForeground(brightness, uiStyle);

    final body = Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            coordination.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: onInverse, fontWeight: FontWeight.w600),
          ),
          Text(
            strings.scheduleCoordinationCandidateCountLabel(
              coordination.candidateDates.length,
            ),
            style: TextStyle(
              color: onInverse.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

    return isGlass
        ? GlassSurface(
            variant: GlassVariant.card,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: body,
            ),
          )
        : Material(
            color: onInverse.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: body,
            ),
          );
  }
}

typedef _SyncStateKey = ({
  bool isDm,
  String conversationId,
  String roomId,
  String eventId,
  String uid,
});

final _syncStateProvider = StreamProvider.family((ref, _SyncStateKey key) {
  return ref
      .watch(calendarEventRepositoryProvider)
      .watchSyncState(
        isDm: key.isDm,
        conversationId: key.conversationId,
        roomId: key.roomId,
        eventId: key.eventId,
        uid: key.uid,
      )
      .handleError((Object e) => debugPrint('CalendarSync: syncState購読失敗 $e'));
});
