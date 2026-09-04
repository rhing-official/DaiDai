import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/calendar_event.dart';
import '../../models/calendar_event_sync.dart';
import '../../providers/accent_color_provider.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/popup_surface_colors.dart';
import '../../widgets/glass/glass_app_bar.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/swipe_gestures.dart';
import 'calendar_event_detail_dialog.dart';
import 'calendar_event_form_dialog.dart';

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

  late DateTime _focusedMonth = _monthOf(DateTime.now());
  Timer? _scrollDismissTimer;

  static DateTime _monthOf(DateTime date) => DateTime(date.year, date.month);

  @override
  void dispose() {
    _scrollDismissTimer?.cancel();
    super.dispose();
  }

  void _goToPreviousMonth() => setState(
    () => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1),
  );

  void _goToNextMonth() => setState(
    () => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1),
  );

  void _goToToday() => setState(() => _focusedMonth = _monthOf(DateTime.now()));

  Future<void> _createEventOn(DateTime day) {
    final now = DateTime.now();
    return showCalendarEventFormDialog(
      context,
      isDm: widget.isDm,
      conversationId: widget.conversationId,
      roomId: widget.roomId,
      currentUserId: widget.currentUser.userId,
      currentUserRhingId: widget.currentUser.rhingId,
      initialDate: DateTime(day.year, day.month, day.day, now.hour, now.minute),
    );
  }

  void _onDayTap(
    BuildContext cellContext,
    DateTime day,
    List<CalendarEvent> events,
  ) {
    if (events.isEmpty) {
      _createEventOn(day);
    } else {
      _showDayEventsPopup(cellContext, day, events);
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
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            currentUserId: widget.currentUser.userId,
            uiStyle: uiStyle,
            strings: strings,
            localeCode: localeCode,
            onAdd: () {
              Navigator.of(context).pop();
              _createEventOn(day);
            },
            onOpenDetail: (event) {
              Navigator.of(context).pop();
              showCalendarEventDetailDialog(
                context,
                isDm: widget.isDm,
                conversationId: widget.conversationId,
                roomId: widget.roomId,
                event: event,
                currentUser: widget.currentUser,
              );
            },
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
    final accent = ref.watch(accentColorProvider);
    final colorScheme = Theme.of(context).colorScheme;

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: StreamBuilder<List<CalendarEvent>>(
                  stream: _eventsStream,
                  builder: (context, snapshot) {
                    final events = snapshot.data ?? const <CalendarEvent>[];
                    final eventsByDate = <DateTime, List<CalendarEvent>>{};
                    for (final event in events) {
                      // 複数日にまたがる予定は、対象日全てにマークを付ける
                      // （2026-09-04修正、以前は開始日にしか登録していなかった）。
                      for (final day in calendarEventDates(event)) {
                        (eventsByDate[day] ??= []).add(event);
                      }
                    }
                    return Column(
                      children: [
                        _MonthHeader(
                          month: _focusedMonth,
                          localeCode: localeCode,
                          todayLabel: strings.calendarTodayButton,
                          onPrevious: _goToPreviousMonth,
                          onNext: _goToNextMonth,
                          onToday: _goToToday,
                        ),
                        const SizedBox(height: 8),
                        _WeekdayHeaderRow(localeCode: localeCode),
                        const SizedBox(height: 4),
                        _MonthGrid(
                          focusedMonth: _focusedMonth,
                          eventsByDate: eventsByDate,
                          isGekiga: uiStyle == AppUiStyle.gekiga,
                          accentColor: accent,
                          colorScheme: colorScheme,
                          onDayTap: (cellContext, day) => _onDayTap(
                            cellContext,
                            day,
                            eventsByDate[day] ?? const [],
                          ),
                        ),
                      ],
                    );
                  },
                ),
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
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final String localeCode;
  final String todayLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

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
        TextButton(onPressed: onToday, child: Text(todayLabel)),
      ],
    );
  }
}

class _WeekdayHeaderRow extends StatelessWidget {
  const _WeekdayHeaderRow({required this.localeCode});

  final String localeCode;

  @override
  Widget build(BuildContext context) {
    // 2023-01-01は日曜日。この週の7日分から曜日ラベル（最短表記）を作る。
    final anchor = DateTime(2023, 1, 1);
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Row(
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
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.focusedMonth,
    required this.eventsByDate,
    required this.isGekiga,
    required this.accentColor,
    required this.colorScheme,
    required this.onDayTap,
  });

  final DateTime focusedMonth;
  final Map<DateTime, List<CalendarEvent>> eventsByDate;
  final bool isGekiga;
  final Color accentColor;
  final ColorScheme colorScheme;
  final void Function(BuildContext cellContext, DateTime day) onDayTap;

  @override
  Widget build(BuildContext context) {
    final year = focusedMonth.year;
    final month = focusedMonth.month;
    final firstOfMonth = DateTime(year, month);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // DateTime.weekday: 月=1...日=7。日曜始まりの先頭余白マス数に変換する。
    final leadingBlanks = firstOfMonth.weekday % 7;
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

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final day in cells)
          _DayCell(
            day: day,
            isCurrentMonth: day.month == month,
            isToday: day == today,
            events: eventsByDate[day] ?? const [],
            isGekiga: isGekiga,
            accentColor: accentColor,
            colorScheme: colorScheme,
            onTap: day.month == month
                ? (cellContext) => onDayTap(cellContext, day)
                : null,
          ),
      ],
    );
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isCurrentMonth,
    required this.isToday,
    required this.events,
    required this.isGekiga,
    required this.accentColor,
    required this.colorScheme,
    required this.onTap,
  });

  final DateTime day;
  final bool isCurrentMonth;
  final bool isToday;
  final List<CalendarEvent> events;
  final bool isGekiga;
  final Color accentColor;
  final ColorScheme colorScheme;

  /// タップしたセル自身の`BuildContext`（`Padding`のRenderBox）を渡す
  /// （2026-09-01追加。予定一覧ポップアップの位置決めに使うため）。
  final void Function(BuildContext cellContext)? onTap;

  @override
  Widget build(BuildContext context) {
    final hasEvents = events.isNotEmpty;
    final dayNumberColor = isCurrentMonth
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.35);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(context),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            // 予定がある日はアクセントカラーを背景の塗りとしてのみ使う
            // （CLAUDE.md規約: テキストにはアクセントカラーを使わない）。
            // 劇画スタイルはアクセントカラーの概念自体を持たないため、
            // 代わりに単色のドットで示す（下記）。
            color: (!isGekiga && hasEvents)
                ? accentColor.withValues(alpha: 0.18)
                : null,
            border: isToday
                ? Border.all(color: colorScheme.outline, width: 2)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${day.day}', style: TextStyle(color: dayNumberColor)),
              if (isGekiga && hasEvents)
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: dayNumberColor,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
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
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.currentUserId,
    required this.uiStyle,
    required this.strings,
    required this.localeCode,
    required this.onAdd,
    required this.onOpenDetail,
  });

  final DateTime day;
  final List<CalendarEvent> events;
  final bool isDm;
  final String conversationId;
  final String roomId;
  final String currentUserId;
  final AppUiStyle uiStyle;
  final Strings strings;
  final String localeCode;
  final VoidCallback onAdd;
  final void Function(CalendarEvent event) onOpenDetail;

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
      );
});
