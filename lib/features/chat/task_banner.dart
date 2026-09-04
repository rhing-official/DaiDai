import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/calendar_event.dart';
import '../../models/calendar_event_rsvp.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/glass/glass_icon_badge.dart';
import '../../widgets/glass/glass_surface.dart';
import '../calendar/calendar_event_detail_dialog.dart';

/// 語らい上部に常時表示するタスクバナー（2026-09-04追加）。現状は「予定への
/// 参加確認が未回答」のみを対象にする。複数件ある場合は最初に追加された
/// （[CalendarEvent.createdAt]が最も古い）ものだけを表示し、他は右端の矢印
/// アイコンでドロップダウン表示する。`ChatScreen.banner`（`chat_screen.dart`）
/// に渡す前提のウィジェット。対象が無ければ`SizedBox.shrink()`を返すため、
/// 呼び出し側は常時組み込んでよい。
class ChatTaskBanner extends ConsumerStatefulWidget {
  const ChatTaskBanner({
    super.key,
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.currentUserId,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final String currentUserId;

  @override
  ConsumerState<ChatTaskBanner> createState() => _ChatTaskBannerState();
}

class _ChatTaskBannerState extends ConsumerState<ChatTaskBanner> {
  StreamSubscription<List<CalendarEvent>>? _eventsSub;
  final Map<String, StreamSubscription<List<CalendarEventRsvp>>> _rsvpSubs = {};
  final Map<String, CalendarEvent> _candidateEvents = {};
  final Map<String, bool> _pendingByEventId = {};
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _eventsSub = ref
        .read(calendarEventRepositoryProvider)
        .watchEvents(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
        )
        .listen(_onEvents);
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    for (final sub in _rsvpSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }

  bool _isUpcoming(CalendarEvent event) {
    final lastRelevant = (event.endAt ?? event.startAt).toDate();
    final cutoff = DateTime(
      lastRelevant.year,
      lastRelevant.month,
      lastRelevant.day,
    ).add(const Duration(days: 1));
    return cutoff.isAfter(DateTime.now());
  }

  void _onEvents(List<CalendarEvent> events) {
    final candidates = {
      for (final e in events)
        if (e.rsvpEnabled && _isUpcoming(e)) e.eventId: e,
    };

    for (final eventId in _rsvpSubs.keys.toList()) {
      if (!candidates.containsKey(eventId)) {
        _rsvpSubs.remove(eventId)?.cancel();
        _pendingByEventId.remove(eventId);
      }
    }

    for (final entry in candidates.entries) {
      if (!_rsvpSubs.containsKey(entry.key)) {
        _rsvpSubs[entry.key] = ref
            .read(calendarEventRepositoryProvider)
            .watchRsvps(
              isDm: widget.isDm,
              conversationId: widget.conversationId,
              roomId: widget.roomId,
              eventId: entry.key,
            )
            .listen((rsvps) => _onRsvps(entry.key, rsvps));
      }
    }

    setState(() {
      _candidateEvents
        ..clear()
        ..addAll(candidates);
    });
  }

  void _onRsvps(String eventId, List<CalendarEventRsvp> rsvps) {
    final event = _candidateEvents[eventId];
    if (event == null) return;
    CalendarEventRsvp? mine;
    for (final rsvp in rsvps) {
      if (rsvp.userId == widget.currentUserId) {
        mine = rsvp;
        break;
      }
    }
    final perDayEnabled = event.rsvpEnabled && event.rsvpPerDay;
    final requiredKeys = perDayEnabled
        ? calendarEventDates(event).map(calendarEventDayKey).toList()
        : const [calendarRsvpSingleKey];
    final pending =
        mine == null ||
        requiredKeys.any((key) => !mine!.dayStatuses.containsKey(key));
    setState(() => _pendingByEventId[eventId] = pending);
  }

  Future<void> _openEvent(CalendarEvent event) async {
    final currentUser = await ref
        .read(userRepositoryProvider)
        .getUser(widget.currentUserId);
    if (currentUser == null || !mounted) return;
    showCalendarEventDetailDialog(
      context,
      isDm: widget.isDm,
      conversationId: widget.conversationId,
      roomId: widget.roomId,
      event: event,
      currentUser: currentUser,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingEvents =
        _pendingByEventId.entries
            .where((e) => e.value)
            .map((e) => _candidateEvents[e.key])
            .whereType<CalendarEvent>()
            .toList()
          ..sort(
            (a, b) => (a.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
              b.createdAt?.millisecondsSinceEpoch ?? 0,
            ),
          );

    if (pendingEvents.isEmpty) return const SizedBox.shrink();

    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final primaryTask = pendingEvents.first;
    final others = pendingEvents.skip(1).toList();

    // 劇画テーマは`primaryContainer`/`onPrimaryContainer`ロールだけ黒赤白へ
    // の上書きが漏れており、Material3のseed生成が残す意図しない青緑になる
    // （`gekiga_theme.dart`参照）。このためこの2ロールはここでは使わず、
    // スタイルごとに意図した色を明示する。
    final background = isGekiga
        ? GekigaColors.panel
        : colorScheme.primaryContainer;
    final foreground = isGekiga
        ? GekigaColors.onPanel
        : colorScheme.onPrimaryContainer;

    Widget arrowButton() => switch (uiStyle) {
      AppUiStyle.gekiga => GekigaIconButton(
        icon: _expanded ? Icons.expand_less : Icons.expand_more,
        size: 28,
        onPressed: () => setState(() => _expanded = !_expanded),
      ),
      AppUiStyle.glass => GlassIconButton(
        icon: _expanded ? Icons.expand_less : Icons.expand_more,
        onPressed: () => setState(() => _expanded = !_expanded),
      ),
      AppUiStyle.flat => IconButton(
        tooltip: '',
        icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
        color: foreground,
        onPressed: () => setState(() => _expanded = !_expanded),
      ),
    };

    final barContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => _openEvent(primaryTask),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.event_outlined, size: 18, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.calendarTaskBannerLabel(primaryTask.title),
                    style: TextStyle(color: foreground),
                  ),
                ),
                if (others.isNotEmpty) arrowButton(),
              ],
            ),
          ),
        ),
        if (_expanded && others.isNotEmpty) ...[
          Divider(
            height: 1,
            thickness: 1,
            color: foreground.withValues(alpha: 0.3),
          ),
          for (final event in others) ...[
            InkWell(
              onTap: () {
                setState(() => _expanded = false);
                _openEvent(event);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_outlined, size: 18, color: foreground),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.calendarTaskBannerLabel(event.title),
                        style: TextStyle(color: foreground),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (event != others.last)
              Divider(
                height: 1,
                thickness: 1,
                color: foreground.withValues(alpha: 0.3),
              ),
          ],
        ],
      ],
    );

    if (isGlass) {
      // 背景の塗り自体はフラットと同じ`background`（アクセントカラーで
      // seedした`colorScheme.primaryContainer`）を使い、その上に
      // `GlassSurface`のぼかし・半透明という「見た目」だけを重ねる
      // （2026-09-04変更、以前は`colorScheme.surface`ベースの中立色任せで
      // アクセントカラーに追従していなかった）。
      return GlassSurface(
        variant: GlassVariant.chrome,
        borderRadius: BorderRadius.zero,
        enableEdgeStroke: false,
        child: Material(
          color: background.withValues(alpha: 0.55),
          child: barContent,
        ),
      );
    }

    final borderColor = isGekiga
        ? GekigaColors.onPanel
        : colorScheme.outlineVariant;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: isGekiga ? 3 : 1),
      ),
      child: Material(color: background, child: barContent),
    );
  }
}
