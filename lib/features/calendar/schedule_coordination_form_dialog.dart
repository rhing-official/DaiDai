import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/calendar_category.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/glass/glass_dialog.dart';
import 'multi_date_picker_dialog.dart';

/// 日程調整の作成ダイアログ（2026-09-05追加）。`calendar_event_form_dialog.dart`
/// と同じ`showDialog`パターン。保存されたら`true`、キャンセルされたら
/// `false`を返す。
Future<bool> showScheduleCoordinationFormDialog(
  BuildContext context, {
  required bool isDm,
  required String conversationId,
  required String roomId,
  required String currentUserId,
  required String currentUserRhingId,
  required DateTime initialCandidateDate,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _ScheduleCoordinationFormDialog(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      currentUserId: currentUserId,
      currentUserRhingId: currentUserRhingId,
      initialCandidateDate: initialCandidateDate,
    ),
  );
  return saved ?? false;
}

class _ScheduleCoordinationFormDialog extends ConsumerStatefulWidget {
  const _ScheduleCoordinationFormDialog({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.currentUserId,
    required this.currentUserRhingId,
    required this.initialCandidateDate,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final String currentUserId;
  final String currentUserRhingId;
  final DateTime initialCandidateDate;

  @override
  ConsumerState<_ScheduleCoordinationFormDialog> createState() =>
      _ScheduleCoordinationFormDialogState();
}

class _ScheduleCoordinationFormDialogState
    extends ConsumerState<_ScheduleCoordinationFormDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  late final List<DateTime> _candidates = [
    _dateOnly(widget.initialCandidateDate),
  ];
  DateTime? _deadline;
  String? _categoryId;
  bool _saving = false;

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // アプリ全体のdialogTheme.constraints（確認ダイアログの横長対策）が
  // Flutter標準のTimePickerDialog/DatePickerDialogにも継承され、レイアウトが
  // 崩れる回帰を防ぐため、この範囲だけdialogThemeを既定に戻す
  // （calendar_event_form_dialog.dartの_resetDialogConstraintsと同じ）。
  Widget _resetDialogConstraints(BuildContext context, Widget? child) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dialogTheme: const DialogThemeData()),
      child: child!,
    );
  }

  Future<void> _pickCandidates() async {
    final result = await showMultiDatePickerDialog(
      context,
      initialSelectedDates: _candidates.toSet(),
    );
    if (result == null || !mounted) return;
    setState(() {
      _candidates
        ..clear()
        ..addAll(result)
        ..sort();
    });
  }

  void _removeCandidate(int index) {
    if (_candidates.length <= 1) return;
    setState(() => _candidates.removeAt(index));
  }

  /// 回答期限を選ぶ（`calendar_event_form_dialog.dart`の`_pickDeadline`と
  /// 同じ実装。ただしここには予定の`_startAt`に相当するものが無いため、
  /// 候補日の最も早い日付を起点にする）。
  Future<void> _pickDeadline() async {
    final initial =
        _deadline ?? _candidates.reduce((a, b) => a.isBefore(b) ? a : b);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(initial.year + 5),
      builder: _resetDialogConstraints,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: _resetDialogConstraints,
    );
    if (time == null) return;
    setState(
      () => _deadline = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    final description = _descriptionController.text.trim();
    try {
      final created = await ref
          .read(scheduleCoordinationRepositoryProvider)
          .createCoordination(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            title: title,
            description: description.isEmpty ? null : description,
            candidateDates: _candidates,
            createdBy: widget.currentUserId,
            deadline: _deadline,
            categoryId: _categoryId,
          );
      // メッセージ画面への通知は副次的な効果であり、失敗しても日程調整の
      // 作成自体は成功として扱う（calendar_event_form_dialog.dartの
      // sendCalendarEventCreatedMessageと同じ設計判断）。
      try {
        if (widget.isDm) {
          await ref
              .read(directMessageRepositoryProvider)
              .sendScheduleCoordinationCreatedMessage(
                dmId: widget.conversationId,
                roomId: widget.roomId,
                senderId: widget.currentUserId,
                senderRhingId: widget.currentUserRhingId,
                coordinationId: created.coordinationId,
                coordinationTitle: created.title,
              );
        } else {
          await ref
              .read(groupRepositoryProvider)
              .sendScheduleCoordinationCreatedMessage(
                groupId: widget.conversationId,
                roomId: widget.roomId,
                senderId: widget.currentUserId,
                senderRhingId: widget.currentUserRhingId,
                coordinationId: created.coordinationId,
                coordinationTitle: created.title,
              );
        }
      } catch (e) {
        debugPrint('[scheduleCoordinationCreatedMessage] failed: $e');
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showAutoDismissBanner(context, message: '$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final localeCode = ref.watch(appLocaleProvider).languageCode;
    final dateFormat = DateFormat.yMMMd(localeCode);
    final deadlineFormat = DateFormat.yMMMd(localeCode).add_Hm();
    final isGlass =
        ProviderScope.containerOf(context).read(appUiStyleProvider) ==
        AppUiStyle.glass;

    final title = Text(strings.scheduleCoordinationCreateDialogTitle);
    final content = SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: strings.calendarTitleFieldHint,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: strings.calendarDescriptionFieldHint,
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<CalendarCategory>>(
              stream: ref
                  .watch(calendarCategoryRepositoryProvider)
                  .watchCategories(
                    isDm: widget.isDm,
                    conversationId: widget.conversationId,
                    roomId: widget.roomId,
                  ),
              builder: (context, snapshot) {
                final categories = snapshot.data ?? const <CalendarCategory>[];
                final validCategoryId =
                    categories.any((c) => c.categoryId == _categoryId)
                    ? _categoryId
                    : null;
                return DropdownButtonFormField<String?>(
                  initialValue: validCategoryId,
                  decoration: InputDecoration(
                    labelText: strings.calendarCategoryPickerLabel,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(strings.calendarCategoryNoneLabel),
                    ),
                    for (final category in categories)
                      DropdownMenuItem(
                        value: category.categoryId,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Color(0xFF000000 | category.color),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(category.name),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                );
              },
            ),
            const Divider(height: 24),
            Text(
              strings.scheduleCoordinationCandidatesSectionTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (var i = 0; i < _candidates.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(dateFormat.format(_candidates[i])),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '',
                  onPressed: _candidates.length > 1
                      ? () => _removeCandidate(i)
                      : null,
                ),
              ),
            TextButton.icon(
              onPressed: _pickCandidates,
              icon: const Icon(Icons.add),
              label: Text(strings.scheduleCoordinationAddCandidateButton),
            ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.calendarRsvpDeadlineLabel),
              subtitle: Text(
                _deadline != null
                    ? deadlineFormat.format(_deadline!)
                    : strings.calendarRsvpDeadlineNoneLabel,
              ),
              trailing: _deadline != null
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: '',
                      onPressed: () => setState(() => _deadline = null),
                    )
                  : null,
              onTap: _pickDeadline,
            ),
          ],
        ),
      ),
    );
    final actions = [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: Text(strings.cancel),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(strings.save),
      ),
    ];

    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
  }
}
