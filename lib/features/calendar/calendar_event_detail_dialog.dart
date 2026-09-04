import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/calendar_event.dart';
import '../../models/calendar_event_rsvp.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/destructive_label.dart';
import '../../widgets/glass/glass_dialog.dart';
import 'calendar_event_form_dialog.dart';

/// 予定の詳細・出欠回答ダイアログ（2026-09-02追加）。予定タップ時の唯一の
/// 導線（`calendar_pane_view.dart`の`_DayEventCard.onTap`）。予定の内容編集
/// は行わない（`calendar_event_form_dialog.dart`は作成専用）。削除のみ
/// 作成者に限り、末尾のアクションから行える。
Future<void> showCalendarEventDetailDialog(
  BuildContext context, {
  required bool isDm,
  required String conversationId,
  required String roomId,
  required CalendarEvent event,
  required AppUser currentUser,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CalendarEventDetailDialog(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      event: event,
      currentUser: currentUser,
    ),
  );
}

typedef _ParticipantsData = ({
  List<String> participantIds,
  Map<String, AppUser> usersById,
});

class _CalendarEventDetailDialog extends ConsumerStatefulWidget {
  const _CalendarEventDetailDialog({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.event,
    required this.currentUser,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final CalendarEvent event;
  final AppUser currentUser;

  @override
  ConsumerState<_CalendarEventDetailDialog> createState() =>
      _CalendarEventDetailDialogState();
}

class _CalendarEventDetailDialogState
    extends ConsumerState<_CalendarEventDetailDialog> {
  late final List<DateTime> _days = calendarEventDates(widget.event);
  late DateTime _selectedDay = _days.first;
  final _noteController = TextEditingController();

  /// 自分の各日の出欠選択（'yyyy-MM-dd' -> 状態。日ごと確認を行わない予定
  /// では[calendarRsvpSingleKey]の1件のみ）。既存の回答があれば初回の
  /// stream受信時に反映する（[_initializedFromExisting]で1回のみ）。
  final Map<String, CalendarRsvpStatus> _myDayStatuses = {};
  bool _initializedFromExisting = false;
  bool _saving = false;

  /// 複数日にまたがる予定で、日ごとに出欠を確認するか
  /// （[CalendarEvent.rsvpEnabled]がfalseなら出欠確認自体を行わない、
  /// 2026-09-02追加）。
  bool get _perDayEnabled =>
      widget.event.rsvpEnabled && widget.event.rsvpPerDay;

  /// 出欠状況表示・自分の回答で現在対象にしている日のキー。日ごと確認を
  /// 行わない予定では常に[calendarRsvpSingleKey]。
  String get _currentDayKey => _perDayEnabled
      ? calendarEventDayKey(_selectedDay)
      : calendarRsvpSingleKey;

  late final Stream<List<CalendarEventRsvp>> _rsvpsStream = ref
      .read(calendarEventRepositoryProvider)
      .watchRsvps(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
        eventId: widget.event.eventId,
      );

  late final Future<_ParticipantsData> _participantsFuture =
      _loadParticipants();

  Future<_ParticipantsData> _loadParticipants() async {
    final ids = await ref
        .read(calendarEventRepositoryProvider)
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

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _initFromExisting(List<CalendarEventRsvp> rsvps) {
    if (_initializedFromExisting) return;
    _initializedFromExisting = true;
    for (final rsvp in rsvps) {
      if (rsvp.userId != widget.currentUser.userId) continue;
      _myDayStatuses.addAll(rsvp.dayStatuses);
      _noteController.text = rsvp.note ?? '';
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final note = _noteController.text.trim();
      await ref
          .read(calendarEventRepositoryProvider)
          .setRsvp(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            eventId: widget.event.eventId,
            userId: widget.currentUser.userId,
            dayStatuses: _myDayStatuses,
            note: note.isEmpty ? null : note,
          );
    } catch (e) {
      // 例外を握りつぶすと保存が失敗しても何も起きたように見えず、ユーザーが
      // 気づけない（calendar_event_form_dialog.dartの_save()と同じ教訓、
      // 2026-09-04発覚）。
      if (mounted) {
        showAutoDismissBanner(context, message: '$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 予定を編集する（回答者0人の間だけ作成者に限り呼べる、2026-09-04追加、
  /// `showCalendarEventFormDialog`参照）。編集ダイアログはこの詳細ダイアログ
  /// の上に重ねて開き、保存されたら（表示中の[widget.event]が古くなるため）
  /// この詳細ダイアログごと閉じる。キャンセル時はこの詳細ダイアログを
  /// 開いたままにする。
  Future<void> _openEditForm() async {
    final saved = await showCalendarEventFormDialog(
      context,
      isDm: widget.isDm,
      conversationId: widget.conversationId,
      roomId: widget.roomId,
      currentUserId: widget.currentUser.userId,
      currentUserRhingId: widget.currentUser.rhingId,
      existingEvent: widget.event,
    );
    if (saved && mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final strings = ref.read(appStringsProvider);
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final title = Text(strings.calendarDeleteConfirmTitle);
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
        .read(calendarEventRepositoryProvider)
        .deleteEvent(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          eventId: widget.event.eventId,
        );
    if (mounted) Navigator.of(context).pop();
  }

  String _statusLabel(Strings strings, CalendarRsvpStatus status) {
    switch (status) {
      case CalendarRsvpStatus.attending:
        return strings.calendarRsvpStatusAttending;
      case CalendarRsvpStatus.notAttending:
        return strings.calendarRsvpStatusNotAttending;
      case CalendarRsvpStatus.late_:
        return strings.calendarRsvpStatusLate;
      case CalendarRsvpStatus.undecided:
        return strings.calendarRsvpStatusUndecided;
    }
  }

  IconData _statusIcon(CalendarRsvpStatus status) {
    switch (status) {
      case CalendarRsvpStatus.attending:
        return Icons.check;
      case CalendarRsvpStatus.notAttending:
        return Icons.close;
      case CalendarRsvpStatus.late_:
        return Icons.schedule;
      case CalendarRsvpStatus.undecided:
        return Icons.help_outline;
    }
  }

  String _eventTimeRangeLabel(Strings strings, String localeCode) {
    final event = widget.event;
    final dateFormat = event.isAllDay
        ? DateFormat.yMMMd(localeCode)
        : DateFormat.yMMMd(localeCode).add_Hm();
    final start = dateFormat.format(event.startAt.toDate());
    if (event.endAt == null) return start;
    final end = dateFormat.format(event.endAt!.toDate());
    return '$start - $end';
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final localeCode = ref.watch(appLocaleProvider).languageCode;
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final event = widget.event;
    final isCreator = widget.currentUser.userId == event.createdBy;
    final dayLabelFormat = DateFormat.Md(localeCode);

    final canEdit = isCreator && event.rsvpCount == 0;
    final deadline = event.rsvpDeadline?.toDate();
    final deadlinePassed = deadline != null && DateTime.now().isAfter(deadline);
    final deadlineFormat = DateFormat.yMMMd(localeCode).add_Hm();
    final title = Row(
      children: [
        Expanded(
          child: Text(
            event.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (canEdit)
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '',
            onPressed: _openEditForm,
          ),
      ],
    );

    final content = SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_eventTimeRangeLabel(strings, localeCode)),
            if (event.location != null && event.location!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(event.location!),
              ),
            if (event.description != null && event.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(event.description!),
              ),
            if (event.rsvpEnabled) ...[
              const Divider(height: 24),
              Text(
                strings.calendarRsvpSectionTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${strings.calendarRsvpDeadlineLabel}: '
                  '${deadline != null ? deadlineFormat.format(deadline) : strings.calendarRsvpDeadlineNoneLabel}'
                  '${deadlinePassed ? strings.calendarRsvpDeadlinePassedLabel : ''}',
                  style: TextStyle(
                    color: deadlinePassed
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ),
              if (_perDayEnabled) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final day in _days)
                      _rsvpChip(
                        context,
                        label: dayLabelFormat.format(day),
                        selected: _isSameDay(day, _selectedDay),
                        onSelected: (_) => setState(() => _selectedDay = day),
                      ),
                  ],
                ),
              ],
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
                  return StreamBuilder<List<CalendarEventRsvp>>(
                    stream: _rsvpsStream,
                    builder: (context, rsvpSnapshot) {
                      final rsvps =
                          rsvpSnapshot.data ?? const <CalendarEventRsvp>[];
                      _initFromExisting(rsvps);
                      final dayKey = _currentDayKey;
                      final byStatus = <CalendarRsvpStatus, List<AppUser>>{
                        for (final status in CalendarRsvpStatus.values)
                          status: [],
                      };
                      final responded = <String>{};
                      for (final rsvp in rsvps) {
                        final status = rsvp.dayStatuses[dayKey];
                        final user = participants.usersById[rsvp.userId];
                        if (status == null || user == null) continue;
                        byStatus[status]!.add(user);
                        responded.add(rsvp.userId);
                      }
                      final noResponse = [
                        for (final id in participants.participantIds)
                          if (!responded.contains(id))
                            ?participants.usersById[id],
                      ];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final status in CalendarRsvpStatus.values)
                            _RsvpGroup(
                              label: _statusLabel(strings, status),
                              users: byStatus[status]!,
                              conversationId: widget.conversationId,
                            ),
                          _RsvpGroup(
                            label: strings.calendarRsvpStatusNoResponse,
                            users: noResponse,
                            conversationId: widget.conversationId,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const Divider(height: 24),
              Text(
                strings.calendarRsvpMySectionTitle,
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
              if (_perDayEnabled)
                for (final day in _days)
                  _MyDayStatusRow(
                    label: dayLabelFormat.format(day),
                    showLabel: true,
                    selected: _myDayStatuses[calendarEventDayKey(day)],
                    disabled: deadlinePassed,
                    onChanged: (status) => setState(() {
                      final key = calendarEventDayKey(day);
                      if (status == null) {
                        _myDayStatuses.remove(key);
                      } else {
                        _myDayStatuses[key] = status;
                      }
                    }),
                    statusLabel: (status) => _statusLabel(strings, status),
                    statusIcon: _statusIcon,
                  )
              else
                _MyDayStatusRow(
                  label: '',
                  showLabel: false,
                  selected: _myDayStatuses[calendarRsvpSingleKey],
                  disabled: deadlinePassed,
                  onChanged: (status) => setState(() {
                    if (status == null) {
                      _myDayStatuses.remove(calendarRsvpSingleKey);
                    } else {
                      _myDayStatuses[calendarRsvpSingleKey] = status;
                    }
                  }),
                  statusLabel: (status) => _statusLabel(strings, status),
                  statusIcon: _statusIcon,
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                enabled: !deadlinePassed,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: strings.calendarRsvpNoteFieldHint,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final actions = [
      if (isCreator)
        TextButton(
          onPressed: _saving ? null : _delete,
          child: IntrinsicWidth(
            child: DestructiveLabel(strings.calendarDeleteAction),
          ),
        ),
      if (event.rsvpEnabled)
        FilledButton(
          onPressed: (_saving || deadlinePassed) ? null : _save,
          child: Text(strings.calendarRsvpSaveButton),
        ),
    ];

    final dialog = isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
    // アプリ全体のdialogTheme.constraints（確認ダイアログの横長対策、
    // maxWidth: 400）だと1日あたり4つの出欠チップが1行に収まらないため、
    // このダイアログだけ広げる。ガラススタイル用のbackgroundColor/elevation/
    // surfaceTintColor（透明化設定）を失わないよう、DialogThemeDataを
    // 作り直さず現在のdialogThemeをcopyWithしてconstraintsだけ差し替える
    // （2026-09-04追加）。
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

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 日付タブ・自分の出欠回答で使う、独立したピル型のチップ（2026-09-04追加、
/// 連結されたSegmentedButtonから変更）。アクセントカラーは選択中チップの
/// 背景の塗りとしてのみ使い、文字・アイコンは`onPrimary`/`onSurfaceVariant`
/// という固定のコントラスト色にする（CLAUDE.md「テキストにアクセントカラー
/// を使わない」規約）。`Theme.of(context).colorScheme`はアクセントカラー・
/// 劇画・ガラスいずれのUIスタイルでも既に正しく導出されているため、
/// スタイル別の分岐は不要。
Widget _rsvpChip(
  BuildContext context, {
  required String label,
  IconData? icon,
  required bool selected,
  required ValueChanged<bool>? onSelected,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final foreground = selected
      ? colorScheme.onPrimary
      : colorScheme.onSurfaceVariant;
  return ChoiceChip(
    avatar: icon != null ? Icon(icon, size: 16, color: foreground) : null,
    label: Text(label, style: TextStyle(color: foreground)),
    selected: selected,
    onSelected: onSelected,
    showCheckmark: false,
    shape: const StadiumBorder(),
    selectedColor: colorScheme.primary,
    backgroundColor: colorScheme.surfaceContainerHighest,
    side: BorderSide(
      color: selected ? colorScheme.primary : colorScheme.outlineVariant,
    ),
  );
}

/// 「自分の回答」1行分（日ごと確認ありなら日付ラベル付き、無ければ
/// ラベル無しで1行だけ、2026-09-02追加）。
class _MyDayStatusRow extends StatelessWidget {
  const _MyDayStatusRow({
    required this.label,
    required this.showLabel,
    required this.selected,
    required this.onChanged,
    required this.statusLabel,
    required this.statusIcon,
    this.disabled = false,
  });

  final String label;
  final bool showLabel;
  final CalendarRsvpStatus? selected;
  final ValueChanged<CalendarRsvpStatus?> onChanged;
  final String Function(CalendarRsvpStatus) statusLabel;
  final IconData Function(CalendarRsvpStatus) statusIcon;

  /// 回答期限を過ぎた予定では回答・回答変更ができないため、チップを操作
  /// 不能にする（2026-09-04追加、実効的な強制はfirestore.rules側）。
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (showLabel) SizedBox(width: 64, child: Text(label)),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final status in CalendarRsvpStatus.values)
                  _rsvpChip(
                    context,
                    label: statusLabel(status),
                    icon: statusIcon(status),
                    selected: selected == status,
                    onSelected: disabled
                        ? null
                        : (isSelected) =>
                              onChanged(isSelected ? status : null),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 出欠グループ1件分（見出し＋対象住人のチップ一覧）。対象が0人なら何も
/// 描画しない。
class _RsvpGroup extends StatelessWidget {
  const _RsvpGroup({
    required this.label,
    required this.users,
    required this.conversationId,
  });

  final String label;
  final List<AppUser> users;
  final String conversationId;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label (${users.length})',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final user in users)
                Chip(
                  avatar: CircleAvatar(
                    backgroundImage:
                        user.effectiveIconFor(conversationId)?.url != null
                        ? NetworkImage(
                            user.effectiveIconFor(conversationId)!.url,
                          )
                        : null,
                    child: user.effectiveIconFor(conversationId)?.url == null
                        ? const Icon(Icons.person, size: 14)
                        : null,
                  ),
                  label: Text(
                    user.effectiveNicknameFor(conversationId)?.text ??
                        '@${user.rhingId}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
