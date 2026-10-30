import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/calendar_category.dart';
import '../../models/calendar_event.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/popup_surface_colors.dart';
import '../../widgets/glass/glass_surface.dart';
import '../chat/button_anchored_menu.dart';
import 'calendar_add_choice_dialog.dart';
import 'calendar_event_form_dialog.dart';
import 'schedule_coordination_form_dialog.dart';

/// カレンダーのドロップダウンの結果（2026-10-30追加）。予定を選んだか、月表示を
/// 開くかのどちらか。
sealed class CalendarPopupResult {
  const CalendarPopupResult();
}

class CalendarPopupEvent extends CalendarPopupResult {
  const CalendarPopupEvent(this.event);
  final CalendarEvent event;
}

class CalendarPopupOpenMonth extends CalendarPopupResult {
  const CalendarPopupOpenMonth();
}

/// 今後の予定（今日以降に終わるもの）を、開始の早い順に並べる。[limit]件まで。
List<CalendarEvent> upcomingEvents(
  List<CalendarEvent> events, {
  required DateTime now,
  int limit = 30,
}) {
  final startOfToday = DateTime(now.year, now.month, now.day);
  final upcoming = [
    for (final event in events)
      if (!(event.endAt ?? event.startAt).toDate().isBefore(startOfToday))
        event,
  ]..sort((a, b) => a.startAt.compareTo(b.startAt));
  return upcoming.take(limit).toList();
}

/// カレンダーボタンの真下に、今後の予定の一覧をポップアップ表示する
/// （2026-10-30追加、`showPollPopup`・`showAlbumPopup`と同じ構成）。予定を選ぶと
/// [CalendarPopupEvent]、ヘッダーの月表示ボタンで[CalendarPopupOpenMonth]を返す
/// （呼び出し元が詳細ダイアログ／月表示のポップアップを開く）。ヘッダーの「＋」は、
/// このポップアップの上に予定・日程調整の追加ダイアログを重ねる。
Future<CalendarPopupResult?> showCalendarPopup(
  BuildContext context, {
  required RelativeRect position,
  GlobalKey? anchorKey,
  required bool isDm,
  required String conversationId,
  required String roomId,
  required AppUser currentUser,
}) {
  return showAnchoredMenu<CalendarPopupResult>(
    context: context,
    position: position,
    anchorKey: anchorKey,
    color: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    items: [
      PopupMenuItem<CalendarPopupResult>(
        enabled: false,
        padding: EdgeInsets.zero,
        // メニューは呼び出し元の外のルートに描かれるため、呼び出し元と同じ
        // プロバイダーの範囲（使い方ガイドの練習用の画面など）を引き継ぐ。
        child: UncontrolledProviderScope(
          container: ProviderScope.containerOf(context),
          child: _CalendarPopupContent(
            isDm: isDm,
            conversationId: conversationId,
            roomId: roomId,
            currentUser: currentUser,
          ),
        ),
      ),
    ],
  );
}

class _CalendarPopupContent extends ConsumerStatefulWidget {
  const _CalendarPopupContent({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.currentUser,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final AppUser currentUser;

  @override
  ConsumerState<_CalendarPopupContent> createState() =>
      _CalendarPopupContentState();
}

class _CalendarPopupContentState extends ConsumerState<_CalendarPopupContent> {
  // 購読は1度だけ作る（再ビルドで取り直さない）。
  late final Stream<List<CalendarEvent>> _eventsStream = ref
      .read(calendarEventRepositoryProvider)
      .watchEvents(
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

  /// 「＋」: 予定／日程調整の選択→追加（今日の日付で開く）。月表示の
  /// 日付タップからの追加（`CalendarPaneView._addOn`）と同じ流れ。
  Future<void> _add() async {
    final choice = await showCalendarAddChoiceDialog(context);
    if (choice == null || !mounted) return;
    final now = DateTime.now();
    switch (choice) {
      case CalendarAddChoice.event:
        await showCalendarEventFormDialog(
          context,
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          currentUserId: widget.currentUser.userId,
          currentUserRhingSeed: widget.currentUser.rhingSeed,
          initialDate: DateTime(
            now.year,
            now.month,
            now.day,
            now.hour,
            now.minute,
          ),
        );
      case CalendarAddChoice.scheduleCoordination:
        await showScheduleCoordinationFormDialog(
          context,
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          currentUserId: widget.currentUser.userId,
          currentUserRhingSeed: widget.currentUser.rhingSeed,
          initialCandidateDate: DateTime(now.year, now.month, now.day),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final localeCode = ref.watch(appLocaleProvider).languageCode;
    final brightness = Theme.of(context).brightness;
    final uiStyle = ref.watch(appUiStyleProvider);
    final onInverse = popupCardForeground(brightness, uiStyle);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.event_outlined, size: 16, color: onInverse),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                strings.calendarFullScreenTitle,
                style: TextStyle(color: onInverse, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.calendar_month_outlined,
                size: 20,
                color: onInverse,
              ),
              tooltip: strings.calendarOpenMonthTooltip,
              onPressed: () =>
                  Navigator.of(context).pop(const CalendarPopupOpenMonth()),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.add, size: 20, color: onInverse),
              tooltip: '',
              onPressed: _add,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<CalendarEvent>>(
          stream: _eventsStream,
          builder: (context, eventsSnapshot) {
            return StreamBuilder<List<CalendarCategory>>(
              stream: _categoriesStream,
              builder: (context, categoriesSnapshot) {
                final categoriesById = {
                  for (final c
                      in categoriesSnapshot.data ?? const <CalendarCategory>[])
                    c.categoryId: c,
                };
                final upcoming = upcomingEvents(
                  eventsSnapshot.data ?? const <CalendarEvent>[],
                  now: DateTime.now(),
                );
                if (upcoming.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      strings.calendarPopupEmptyMessage,
                      style: TextStyle(color: onInverse),
                    ),
                  );
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final event in upcoming)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _CalendarPopupCard(
                              event: event,
                              category: categoriesById[event.categoryId],
                              uiStyle: uiStyle,
                              strings: strings,
                              localeCode: localeCode,
                              onTap: () => Navigator.of(
                                context,
                              ).pop(CalendarPopupEvent(event)),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );

    return SizedBox(
      width: 300,
      child: Container(
        decoration: BoxDecoration(
          color: popupCardBackground(brightness, uiStyle),
          border: Border.all(color: popupCardBorder(brightness, uiStyle)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(padding: const EdgeInsets.all(12), child: content),
      ),
    );
  }
}

/// ポップアップ内の予定1件分のカード（`_PollPopupCard`と同じ構成）。左端の色の帯は、
/// 月表示と同じカテゴリの色（無ければ帯なし）。
class _CalendarPopupCard extends StatelessWidget {
  const _CalendarPopupCard({
    required this.event,
    required this.category,
    required this.uiStyle,
    required this.strings,
    required this.localeCode,
    required this.onTap,
  });

  final CalendarEvent event;
  final CalendarCategory? category;
  final AppUiStyle uiStyle;
  final Strings strings;
  final String localeCode;
  final VoidCallback onTap;

  String _when() {
    final start = event.startAt.toDate();
    final date = DateFormat.MMMEd(localeCode).format(start);
    if (event.isAllDay) return '$date ${strings.calendarAllDayLabel}';
    return '$date ${DateFormat.Hm(localeCode).format(start)}';
  }

  @override
  Widget build(BuildContext context) {
    final isGlass = uiStyle == AppUiStyle.glass;
    final brightness = Theme.of(context).brightness;
    final onInverse = popupCardForeground(brightness, uiStyle);
    final categoryColor = category == null
        ? null
        : Color(0xFF000000 | category!.color);

    final body = Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          if (categoryColor != null) ...[
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                color: categoryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onInverse,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _when(),
                  style: TextStyle(
                    color: onInverse.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
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
