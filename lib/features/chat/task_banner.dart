import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/calendar_event.dart';
import '../../models/calendar_event_rsvp.dart';
import '../../models/poll.dart';
import '../../models/poll_response.dart';
import '../../models/schedule_coordination.dart';
import '../../models/schedule_coordination_response.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/glass/glass_icon_badge.dart';
import '../../widgets/glass/glass_surface.dart';
import '../calendar/calendar_event_detail_dialog.dart';
import '../calendar/schedule_coordination_detail_dialog.dart';
import '../poll/poll_detail_dialog.dart';

/// 語らい上部に常時表示するタスクバナー（2026-09-04追加、2026-09-05に
/// 日程調整の未回答も統合表示するよう拡張）。「予定への参加確認が未回答」
/// と「日程調整が未回答」を1つのリストにまとめ、複数件ある場合は最初に
/// 追加された（`createdAt`が最も古い）ものだけを表示し、他は右端の矢印
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

/// バナーに表示する1件分のタスク（予定/日程調整、2026-09-05追加）。
sealed class _PendingTask {
  const _PendingTask({
    required this.title,
    required this.createdAt,
    required this.icon,
  });

  final String title;
  final Timestamp? createdAt;
  final IconData icon;
}

class _PendingEventTask extends _PendingTask {
  _PendingEventTask(this.event)
    : super(
        title: event.title,
        createdAt: event.createdAt,
        icon: Icons.event_outlined,
      );

  final CalendarEvent event;
}

class _PendingCoordinationTask extends _PendingTask {
  _PendingCoordinationTask(this.coordination)
    : super(
        title: coordination.title,
        createdAt: coordination.createdAt,
        icon: Icons.event_available_outlined,
      );

  final ScheduleCoordination coordination;
}

class _PendingPollTask extends _PendingTask {
  _PendingPollTask(this.poll)
    : super(
        title: poll.question,
        createdAt: poll.createdAt,
        icon: Icons.how_to_vote_outlined,
      );

  final Poll poll;
}

class _ChatTaskBannerState extends ConsumerState<ChatTaskBanner> {
  StreamSubscription<List<CalendarEvent>>? _eventsSub;
  final Map<String, StreamSubscription<List<CalendarEventRsvp>>> _rsvpSubs = {};
  final Map<String, CalendarEvent> _candidateEvents = {};
  final Map<String, bool> _pendingByEventId = {};

  StreamSubscription<List<ScheduleCoordination>>? _coordinationsSub;
  final Map<String, StreamSubscription<List<ScheduleCoordinationResponse>>>
  _responseSubs = {};
  final Map<String, ScheduleCoordination> _candidateCoordinations = {};
  final Map<String, bool> _pendingByCoordinationId = {};

  StreamSubscription<List<Poll>>? _pollsSub;
  final Map<String, StreamSubscription<PollResponse?>> _pollResponseSubs = {};
  final Map<String, Poll> _candidatePolls = {};
  final Map<String, bool> _pendingByPollId = {};

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
    _coordinationsSub = ref
        .read(scheduleCoordinationRepositoryProvider)
        .watchCoordinations(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
        )
        .listen(_onCoordinations);
    _pollsSub = ref
        .read(pollRepositoryProvider)
        .watchPolls(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
        )
        .listen(_onPolls);
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    for (final sub in _rsvpSubs.values) {
      sub.cancel();
    }
    _coordinationsSub?.cancel();
    for (final sub in _responseSubs.values) {
      sub.cancel();
    }
    _pollsSub?.cancel();
    for (final sub in _pollResponseSubs.values) {
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

  /// 日程調整の対象判定は「未確定であること」そのものにする（2026-09-05
  /// 追加）。予定と違い日程調整には「もう過去のことになった」に相当する
  /// 概念が無く（開催されるのは確定後の予定側）、確定した時点で自然に
  /// リストから外れる。
  void _onCoordinations(List<ScheduleCoordination> coordinations) {
    final candidates = {
      for (final c in coordinations)
        if (!c.isFinalized) c.coordinationId: c,
    };

    for (final id in _responseSubs.keys.toList()) {
      if (!candidates.containsKey(id)) {
        _responseSubs.remove(id)?.cancel();
        _pendingByCoordinationId.remove(id);
      }
    }

    for (final entry in candidates.entries) {
      if (!_responseSubs.containsKey(entry.key)) {
        _responseSubs[entry.key] = ref
            .read(scheduleCoordinationRepositoryProvider)
            .watchResponses(
              isDm: widget.isDm,
              conversationId: widget.conversationId,
              roomId: widget.roomId,
              coordinationId: entry.key,
            )
            .listen((responses) => _onResponses(entry.key, responses));
      }
    }

    setState(() {
      _candidateCoordinations
        ..clear()
        ..addAll(candidates);
    });
  }

  void _onResponses(
    String coordinationId,
    List<ScheduleCoordinationResponse> responses,
  ) {
    if (!_candidateCoordinations.containsKey(coordinationId)) return;
    final pending = !responses.any((r) => r.userId == widget.currentUserId);
    setState(() => _pendingByCoordinationId[coordinationId] = pending);
  }

  /// 投票の対象判定は「未締切であること」そのものにする（2026-09-06追加）。
  /// 日程調整の「未確定」に相当する概念が投票には無いため。
  void _onPolls(List<Poll> polls) {
    final candidates = {
      for (final p in polls)
        if (!p.isClosed) p.pollId: p,
    };

    for (final id in _pollResponseSubs.keys.toList()) {
      if (!candidates.containsKey(id)) {
        _pollResponseSubs.remove(id)?.cancel();
        _pendingByPollId.remove(id);
      }
    }

    for (final entry in candidates.entries) {
      if (!_pollResponseSubs.containsKey(entry.key)) {
        _pollResponseSubs[entry.key] = ref
            .read(pollRepositoryProvider)
            .watchMyResponse(
              isDm: widget.isDm,
              conversationId: widget.conversationId,
              roomId: widget.roomId,
              pollId: entry.key,
              userId: widget.currentUserId,
            )
            .listen((response) => _onPollResponse(entry.key, response));
      }
    }

    setState(() {
      _candidatePolls
        ..clear()
        ..addAll(candidates);
    });
  }

  /// 自分の回答（[PollRepository.watchMyResponse]）だけを購読することで、
  /// 匿名投票でも他人の投票内容を一切読まずに未回答判定できる
  /// （firestore.rulesも匿名投票のresponsesは本人以外読めない）。
  void _onPollResponse(String pollId, PollResponse? response) {
    if (!_candidatePolls.containsKey(pollId)) return;
    setState(() => _pendingByPollId[pollId] = response == null);
  }

  Future<void> _openTask(_PendingTask task) async {
    final currentUser = await ref
        .read(userRepositoryProvider)
        .getUser(widget.currentUserId);
    if (currentUser == null || !mounted) return;
    switch (task) {
      case _PendingEventTask(:final event):
        showCalendarEventDetailDialog(
          context,
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          event: event,
          currentUser: currentUser,
        );
      case _PendingCoordinationTask(:final coordination):
        showScheduleCoordinationDetailDialog(
          context,
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          coordination: coordination,
          currentUser: currentUser,
        );
      case _PendingPollTask(:final poll):
        showPollDetailDialog(
          context,
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          poll: poll,
          currentUser: currentUser,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingEvents = _pendingByEventId.entries
        .where((e) => e.value)
        .map((e) => _candidateEvents[e.key])
        .whereType<CalendarEvent>();
    final pendingCoordinations = _pendingByCoordinationId.entries
        .where((e) => e.value)
        .map((e) => _candidateCoordinations[e.key])
        .whereType<ScheduleCoordination>();
    final pendingPolls = _pendingByPollId.entries
        .where((e) => e.value)
        .map((e) => _candidatePolls[e.key])
        .whereType<Poll>();

    final pendingTasks =
        <_PendingTask>[
          for (final event in pendingEvents) _PendingEventTask(event),
          for (final coordination in pendingCoordinations)
            _PendingCoordinationTask(coordination),
          for (final poll in pendingPolls) _PendingPollTask(poll),
        ]..sort(
          (a, b) => (a.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
            b.createdAt?.millisecondsSinceEpoch ?? 0,
          ),
        );

    if (pendingTasks.isEmpty) return const SizedBox.shrink();

    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final primaryTask = pendingTasks.first;
    final others = pendingTasks.skip(1).toList();

    String labelFor(_PendingTask task) => switch (task) {
      _PendingEventTask() => strings.calendarTaskBannerLabel(task.title),
      _PendingCoordinationTask() => strings.scheduleCoordinationTaskBannerLabel(
        task.title,
      ),
      _PendingPollTask() => strings.pollTaskBannerLabel(task.title),
    };

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
          onTap: () => _openTask(primaryTask),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(primaryTask.icon, size: 18, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    labelFor(primaryTask),
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
          for (final task in others) ...[
            InkWell(
              onTap: () {
                setState(() => _expanded = false);
                _openTask(task);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(task.icon, size: 18, color: foreground),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        labelFor(task),
                        style: TextStyle(color: foreground),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (task != others.last)
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
