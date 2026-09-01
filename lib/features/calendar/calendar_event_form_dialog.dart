import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/calendar_event.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/glass/glass_dialog.dart';

/// 予定の作成・編集ダイアログ（2026-09-01追加）。[existing]がnullなら作成、
/// 指定すれば編集（削除ボタンも表示する）。`AlbumRepository`の作成/リネーム
/// ダイアログと同じ`showDialog`パターン。
Future<void> showCalendarEventFormDialog(
  BuildContext context, {
  required bool isDm,
  required String conversationId,
  required String roomId,
  required String currentUserId,
  CalendarEvent? existing,
  DateTime? initialDate,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CalendarEventFormDialog(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      currentUserId: currentUserId,
      existing: existing,
      initialDate: initialDate,
    ),
  );
}

class _CalendarEventFormDialog extends ConsumerStatefulWidget {
  const _CalendarEventFormDialog({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.currentUserId,
    required this.existing,
    this.initialDate,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final String currentUserId;
  final CalendarEvent? existing;

  /// 月表示カレンダーで予定の無い日をタップして新規作成する場合の初期日付
  /// （2026-09-01追加）。[existing]がnullの場合のみ意味を持つ。
  final DateTime? initialDate;

  @override
  ConsumerState<_CalendarEventFormDialog> createState() =>
      _CalendarEventFormDialogState();
}

class _CalendarEventFormDialogState
    extends ConsumerState<_CalendarEventFormDialog> {
  late final _titleController = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _locationController = TextEditingController(
    text: widget.existing?.location ?? '',
  );
  late bool _isAllDay = widget.existing?.isAllDay ?? false;
  late DateTime _startAt =
      widget.existing?.startAt.toDate() ??
      widget.initialDate ??
      DateTime.now().add(const Duration(hours: 1));
  late DateTime? _endAt = widget.existing?.endAt?.toDate();
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await _pickDateTime(_startAt);
    if (picked == null) return;
    setState(() {
      _startAt = picked;
      if (_endAt != null && _endAt!.isBefore(_startAt)) {
        _endAt = null;
      }
    });
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDateTime(_endAt ?? _startAt);
    if (picked == null) return;
    setState(() => _endAt = picked);
  }

  // アプリ全体のdialogTheme.constraints（確認ダイアログの横長対策、
  // 2026-09-01追加）がFlutter標準のTimePickerDialog/DatePickerDialogにも
  // 継承され、レイアウトが崩れる回帰が発覚した。builder経由でこの範囲だけ
  // dialogThemeを既定（制約なし）に戻し、標準ピッカーは本来のサイズで
  // 表示させる。
  Widget _resetDialogConstraints(BuildContext context, Widget? child) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dialogTheme: const DialogThemeData()),
      child: child!,
    );
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(initial.year + 5),
      builder: _resetDialogConstraints,
    );
    if (date == null || !mounted) return null;
    if (_isAllDay) return DateTime(date.year, date.month, date.day);
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: _resetDialogConstraints,
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    final repo = ref.read(calendarEventRepositoryProvider);
    final description = _descriptionController.text.trim();
    final location = _locationController.text.trim();
    try {
      if (widget.existing == null) {
        await repo.createEvent(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          title: title,
          description: description.isEmpty ? null : description,
          startAt: _startAt,
          endAt: _endAt,
          isAllDay: _isAllDay,
          location: location.isEmpty ? null : location,
          createdBy: widget.currentUserId,
        );
      } else {
        await repo.updateEvent(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          eventId: widget.existing!.eventId,
          updatedBy: widget.currentUserId,
          title: title,
          description: description.isEmpty ? null : description,
          startAt: _startAt,
          endAt: _endAt,
          isAllDay: _isAllDay,
          location: location.isEmpty ? null : location,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // 例外を握りつぶすと保存が失敗しても何も起きたように見えず、ユーザーが
      // 気づけない（2026-09-01発覚、firestore.rulesの不整合で常に失敗していた
      // 際にこの無言失敗のせいで原因特定が難航した）。ダイアログは閉じずに
      // エラーを表示し、再試行できるようにする。
      if (mounted) {
        showAutoDismissBanner(context, message: '$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final strings = ref.read(appStringsProvider);
    final isGlass =
        ProviderScope.containerOf(context).read(appUiStyleProvider) ==
        AppUiStyle.glass;
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
            // colorScheme.errorはダークテーマ下でコントラストが不十分に
            // なるため固定の濃い赤にする（CLAUDE.md記載の既存の教訓）。
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
          eventId: widget.existing!.eventId,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final localeCode = ref.watch(appLocaleProvider).languageCode;
    final dateFormat = _isAllDay
        ? DateFormat.yMMMd(localeCode)
        : DateFormat.yMMMd(localeCode).add_Hm();
    final isEditing = widget.existing != null;
    final isGlass =
        ProviderScope.containerOf(context).read(appUiStyleProvider) ==
        AppUiStyle.glass;

    final title = Text(
      isEditing
          ? strings.calendarEditDialogTitle
          : strings.calendarCreateDialogTitle,
    );
    final content = SingleChildScrollView(
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.calendarAllDayLabel),
            value: _isAllDay,
            onChanged: (value) => setState(() => _isAllDay = value),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.calendarStartLabel),
            subtitle: Text(dateFormat.format(_startAt)),
            onTap: _pickStart,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.calendarEndLabel),
            subtitle: Text(_endAt != null ? dateFormat.format(_endAt!) : '-'),
            trailing: _endAt != null
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: '',
                    onPressed: () => setState(() => _endAt = null),
                  )
                : null,
            onTap: _pickEnd,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _locationController,
            decoration: InputDecoration(
              hintText: strings.calendarLocationFieldHint,
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
        ],
      ),
    );
    final actions = [
      if (isEditing)
        TextButton(
          onPressed: _saving ? null : _delete,
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          child: Text(strings.calendarDeleteAction),
        ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
