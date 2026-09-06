import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/schedule_coordination.dart';
import '../../models/schedule_coordination_response.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/destructive_label.dart';
import '../../widgets/glass/glass_dialog.dart';
import 'calendar_chip.dart';
import 'calendar_event_detail_dialog.dart';
import 'calendar_event_form_dialog.dart';

/// 日程調整の詳細・投票ダイアログ（2026-09-05追加）。日程調整開始通知
/// メッセージのタップ時、カレンダー月表示のカードタップ時、タスクバナーの
/// タップ時いずれからも開く唯一の導線。`calendar_event_detail_dialog.dart`
/// と同じ`showDialog`パターン。
Future<void> showScheduleCoordinationDetailDialog(
  BuildContext context, {
  required bool isDm,
  required String conversationId,
  required String roomId,
  required ScheduleCoordination coordination,
  required AppUser currentUser,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ScheduleCoordinationDetailDialog(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      coordination: coordination,
      currentUser: currentUser,
    ),
  );
}

typedef _ParticipantsData = ({
  List<String> participantIds,
  Map<String, AppUser> usersById,
});

class _ScheduleCoordinationDetailDialog extends ConsumerStatefulWidget {
  const _ScheduleCoordinationDetailDialog({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.coordination,
    required this.currentUser,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final ScheduleCoordination coordination;
  final AppUser currentUser;

  @override
  ConsumerState<_ScheduleCoordinationDetailDialog> createState() =>
      _ScheduleCoordinationDetailDialogState();
}

class _ScheduleCoordinationDetailDialogState
    extends ConsumerState<_ScheduleCoordinationDetailDialog> {
  /// 自分の各候補の投票（[scheduleCoordinationCandidateKey] -> 投票）。既存の
  /// 回答があれば初回のstream受信時に反映する（[_initializedFromExisting]で
  /// 1回のみ）。
  final Map<String, ScheduleCoordinationVote> _myVotes = {};
  bool _initializedFromExisting = false;
  bool _saving = false;
  bool _finalizing = false;

  late final Stream<List<ScheduleCoordinationResponse>> _responsesStream = ref
      .read(scheduleCoordinationRepositoryProvider)
      .watchResponses(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
        coordinationId: widget.coordination.coordinationId,
      );

  late final Future<_ParticipantsData> _participantsFuture =
      _loadParticipants();

  Future<_ParticipantsData> _loadParticipants() async {
    final ids = await ref
        .read(scheduleCoordinationRepositoryProvider)
        .participantIds(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
        );
    final users = await ref.read(userRepositoryProvider).getUsersByIds(ids);
    return (
      participantIds: ids,
      usersById: {for (final user in users) user.userId: user},
    );
  }

  void _initFromExisting(List<ScheduleCoordinationResponse> responses) {
    if (_initializedFromExisting) return;
    _initializedFromExisting = true;
    for (final response in responses) {
      if (response.userId != widget.currentUser.userId) continue;
      _myVotes.addAll(response.votes);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(scheduleCoordinationRepositoryProvider)
          .setResponse(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            coordinationId: widget.coordination.coordinationId,
            userId: widget.currentUser.userId,
            votes: _myVotes,
          );
    } catch (e) {
      if (mounted) showAutoDismissBanner(context, message: '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 候補[index]（日付[candidateDate]）で確定する（2026-09-05追加）。通常の
  /// 予定追加フォームをその日付で開き、保存されたら日程調整側に
  /// finalizedCandidateIndex/finalizedEventIdを書き込む。イベント作成後の
  /// finalize書き込みが失敗した場合は、イベント自体は既に作成済みのため
  /// このダイアログを開いたままエラーを表示し、再試行できるようにする。
  Future<void> _finalize(int index, DateTime candidateDate) async {
    final strings = ref.read(appStringsProvider);
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final title = Text(strings.scheduleCoordinationFinalizeConfirmTitle);
        final content = Text(
          strings.scheduleCoordinationFinalizeConfirmMessage,
        );
        final actions = [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.scheduleCoordinationFinalizeAction),
          ),
        ];
        return isGlass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : AlertDialog(title: title, content: content, actions: actions);
      },
    );
    if (confirmed != true || !mounted) return;

    final result = await showCalendarEventFormDialog(
      context,
      isDm: widget.isDm,
      conversationId: widget.conversationId,
      roomId: widget.roomId,
      currentUserId: widget.currentUser.userId,
      currentUserRhingId: widget.currentUser.rhingId,
      initialDate: candidateDate,
    );
    if (result == null || !mounted) return;

    setState(() => _finalizing = true);
    try {
      await ref
          .read(scheduleCoordinationRepositoryProvider)
          .finalize(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            coordinationId: widget.coordination.coordinationId,
            finalizedCandidateIndex: index,
            finalizedEventId: result.eventId,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // イベント自体は既に作成済みのため再スローせず、ダイアログを開いた
      // ままエラーを表示してfinalizeの書き込みだけ再試行できるようにする。
      if (mounted) showAutoDismissBanner(context, message: '$e');
    } finally {
      if (mounted) setState(() => _finalizing = false);
    }
  }

  Future<void> _openFinalizedEvent() async {
    final eventId = widget.coordination.finalizedEventId;
    if (eventId == null) return;
    final event = await ref
        .read(calendarEventRepositoryProvider)
        .getEvent(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          eventId: eventId,
        );
    if (event == null || !mounted) return;
    showCalendarEventDetailDialog(
      context,
      isDm: widget.isDm,
      conversationId: widget.conversationId,
      roomId: widget.roomId,
      event: event,
      currentUser: widget.currentUser,
    );
  }

  Future<void> _delete() async {
    final strings = ref.read(appStringsProvider);
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final title = Text(strings.scheduleCoordinationDeleteConfirmTitle);
        final content = Text(strings.calendarDeleteConfirmMessage);
        final actions = [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: Text(strings.delete),
          ),
        ];
        return isGlass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : AlertDialog(title: title, content: content, actions: actions);
      },
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(scheduleCoordinationRepositoryProvider)
        .deleteCoordination(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          coordinationId: widget.coordination.coordinationId,
        );
    if (mounted) Navigator.of(context).pop();
  }

  String _voteLabel(Strings strings, ScheduleCoordinationVote vote) {
    switch (vote) {
      case ScheduleCoordinationVote.yes:
        return strings.scheduleCoordinationVoteYes;
      case ScheduleCoordinationVote.maybe:
        return strings.scheduleCoordinationVoteMaybe;
      case ScheduleCoordinationVote.no:
        return strings.scheduleCoordinationVoteNo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final localeCode = ref.watch(appLocaleProvider).languageCode;
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final coordination = widget.coordination;
    final isCreator = widget.currentUser.userId == coordination.createdBy;
    final dateFormat = DateFormat.yMMMEd(localeCode);
    final deadlineFormat = DateFormat.yMMMd(localeCode).add_Hm();

    final deadline = coordination.deadline?.toDate();
    final deadlinePassed = deadline != null && DateTime.now().isAfter(deadline);

    final title = Text(
      coordination.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    final content = SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (coordination.description != null &&
                coordination.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(coordination.description!),
              ),
            Text(
              '${strings.calendarRsvpDeadlineLabel}: '
              '${deadline != null ? deadlineFormat.format(deadline) : strings.calendarRsvpDeadlineNoneLabel}'
              '${deadlinePassed ? strings.calendarRsvpDeadlinePassedLabel : ''}',
              style: TextStyle(
                color: deadlinePassed
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
            const Divider(height: 24),
            if (coordination.isFinalized) ...[
              Text(
                strings.scheduleCoordinationFinalizedLabel(
                  dateFormat.format(
                    coordination
                        .candidateDates[coordination.finalizedCandidateIndex!]
                        .toDate(),
                  ),
                ),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _openFinalizedEvent,
                child: Text(strings.scheduleCoordinationOpenEventAction),
              ),
            ] else ...[
              Text(
                strings.scheduleCoordinationCandidatesSectionTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (deadlinePassed)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    strings.calendarRsvpDeadlinePassedNotice,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              FutureBuilder<_ParticipantsData>(
                future: _participantsFuture,
                builder: (context, participantsSnapshot) {
                  final participants = participantsSnapshot.data;
                  if (participants == null) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return StreamBuilder<List<ScheduleCoordinationResponse>>(
                    stream: _responsesStream,
                    builder: (context, responseSnapshot) {
                      final responses =
                          responseSnapshot.data ??
                          const <ScheduleCoordinationResponse>[];
                      _initFromExisting(responses);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var i = 0;
                            i < coordination.candidateDates.length;
                            i++
                          )
                            _CandidateSection(
                              label: dateFormat.format(
                                coordination.candidateDates[i].toDate(),
                              ),
                              candidateKey: scheduleCoordinationCandidateKey(i),
                              myVote:
                                  _myVotes[scheduleCoordinationCandidateKey(i)],
                              disabled: deadlinePassed,
                              onVoteChanged: (vote) => setState(() {
                                final key = scheduleCoordinationCandidateKey(i);
                                if (vote == null) {
                                  _myVotes.remove(key);
                                } else {
                                  _myVotes[key] = vote;
                                }
                              }),
                              voteLabel: (vote) => _voteLabel(strings, vote),
                              responses: responses,
                              participants: participants,
                              conversationId: widget.conversationId,
                              strings: strings,
                              isCreator: isCreator,
                              finalizing: _finalizing,
                              onFinalize: () => _finalize(
                                i,
                                coordination.candidateDates[i].toDate(),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );

    final actions = [
      if (isCreator)
        TextButton(
          onPressed: (_saving || _finalizing) ? null : _delete,
          child: IntrinsicWidth(
            child: DestructiveLabel(strings.scheduleCoordinationDeleteAction),
          ),
        ),
      if (!coordination.isFinalized)
        FilledButton(
          onPressed: (_saving || _finalizing || deadlinePassed) ? null : _save,
          child: Text(strings.calendarRsvpSaveButton),
        ),
    ];

    final dialog = isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
    // 候補が複数並ぶため、既定の確認ダイアログ幅(maxWidth: 400)より広げる
    // （calendar_event_detail_dialog.dartと同じ理由・同じ実装）。
    final ambientTheme = Theme.of(context);
    return Theme(
      data: ambientTheme.copyWith(
        dialogTheme: ambientTheme.dialogTheme.copyWith(
          constraints: const BoxConstraints(maxWidth: 560),
        ),
      ),
      child: dialog,
    );
  }
}

/// 候補1件分の表示（日付ラベル＋自分の投票チップ＋回答集計＋（作成者のみ）
/// 確定ボタン、2026-09-05追加）。
class _CandidateSection extends StatelessWidget {
  const _CandidateSection({
    required this.label,
    required this.candidateKey,
    required this.myVote,
    required this.disabled,
    required this.onVoteChanged,
    required this.voteLabel,
    required this.responses,
    required this.participants,
    required this.conversationId,
    required this.strings,
    required this.isCreator,
    required this.finalizing,
    required this.onFinalize,
  });

  final String label;
  final String candidateKey;
  final ScheduleCoordinationVote? myVote;
  final bool disabled;
  final ValueChanged<ScheduleCoordinationVote?> onVoteChanged;
  final String Function(ScheduleCoordinationVote) voteLabel;
  final List<ScheduleCoordinationResponse> responses;
  final _ParticipantsData participants;
  final String conversationId;
  final Strings strings;
  final bool isCreator;
  final bool finalizing;
  final VoidCallback onFinalize;

  @override
  Widget build(BuildContext context) {
    final byVote = <ScheduleCoordinationVote, List<AppUser>>{
      for (final vote in ScheduleCoordinationVote.values) vote: [],
    };
    final responded = <String>{};
    for (final response in responses) {
      final vote = response.votes[candidateKey];
      final user = participants.usersById[response.userId];
      if (vote == null || user == null) continue;
      byVote[vote]!.add(user);
      responded.add(response.userId);
    }
    final noResponse = [
      for (final id in participants.participantIds)
        if (!responded.contains(id)) ?participants.usersById[id],
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (final vote in ScheduleCoordinationVote.values)
                calendarChoiceChip(
                  context,
                  label: voteLabel(vote),
                  selected: myVote == vote,
                  onSelected: disabled
                      ? null
                      : (selected) => onVoteChanged(selected ? vote : null),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (final vote in ScheduleCoordinationVote.values)
            CalendarResponseGroup(
              label: voteLabel(vote),
              users: byVote[vote]!,
              conversationId: conversationId,
            ),
          CalendarResponseGroup(
            label: strings.calendarRsvpStatusNoResponse,
            users: noResponse,
            conversationId: conversationId,
          ),
          if (isCreator)
            TextButton(
              onPressed: finalizing ? null : onFinalize,
              child: Text(strings.scheduleCoordinationFinalizeAction),
            ),
        ],
      ),
    );
  }
}
