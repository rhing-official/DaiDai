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

/// 予定の作成・編集ダイアログ（2026-09-01追加）。作成後の内容編集は出欠
/// 回答済みの住人との齟齬を避けるため2026-09-02に一旦廃止したが、回答者が
/// 1人もいない（[CalendarEvent.rsvpCount] == 0）間だけ作成者に限り
/// 2026-09-04に再度許可した（[existingEvent]非null時が編集モード、
/// firestore.rules側でも同条件を強制）。詳細・出欠は
/// `calendar_event_detail_dialog.dart`。`AlbumRepository`の作成ダイアログと
/// 同じ`showDialog`パターン。保存されたら`true`、キャンセルされたら`false`
/// を返す。
Future<bool> showCalendarEventFormDialog(
  BuildContext context, {
  required bool isDm,
  required String conversationId,
  required String roomId,
  required String currentUserId,
  required String currentUserRhingId,
  DateTime? initialDate,
  CalendarEvent? existingEvent,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _CalendarEventFormDialog(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      currentUserId: currentUserId,
      currentUserRhingId: currentUserRhingId,
      initialDate: initialDate,
      existingEvent: existingEvent,
    ),
  );
  return saved ?? false;
}

class _CalendarEventFormDialog extends ConsumerStatefulWidget {
  const _CalendarEventFormDialog({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.currentUserId,
    required this.currentUserRhingId,
    this.initialDate,
    this.existingEvent,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final String currentUserId;
  final String currentUserRhingId;

  /// 月表示カレンダーで予定の無い日をタップして新規作成する場合の初期日付
  /// （2026-09-01追加）。
  final DateTime? initialDate;

  /// 非nullなら編集モード（2026-09-04追加、回答者0人の予定のみ呼び出し元
  /// `calendar_event_detail_dialog.dart`が渡す）。
  final CalendarEvent? existingEvent;

  @override
  ConsumerState<_CalendarEventFormDialog> createState() =>
      _CalendarEventFormDialogState();
}

class _CalendarEventFormDialogState
    extends ConsumerState<_CalendarEventFormDialog> {
  late final _titleController = TextEditingController(
    text: widget.existingEvent?.title ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.existingEvent?.description ?? '',
  );
  late final _locationController = TextEditingController(
    text: widget.existingEvent?.location ?? '',
  );
  late bool _isAllDay = widget.existingEvent?.isAllDay ?? false;
  late DateTime _startAt =
      widget.existingEvent?.startAt.toDate() ??
      widget.initialDate ??
      DateTime.now().add(const Duration(hours: 1));
  late DateTime? _endAt = widget.existingEvent?.endAt?.toDate();
  late bool _rsvpEnabled = widget.existingEvent?.rsvpEnabled ?? true;
  late bool _rsvpPerDay = widget.existingEvent?.rsvpPerDay ?? false;
  late DateTime? _rsvpDeadline = widget.existingEvent?.rsvpDeadline?.toDate();
  bool _saving = false;

  bool get _isEditing => widget.existingEvent != null;

  /// 終日トグルをONにする直前の開始・終了日時（時刻・複数日の範囲込み）の
  /// 一時退避先（2026-09-04追加）。ONにすると[_startAt]/[_endAt]は日付のみに
  /// 削られるため、再度OFFに戻したときにここから元の値を復元する。
  DateTime? _preAllDayStartAt;
  DateTime? _preAllDayEndAt;
  bool _hasPreAllDaySnapshot = false;

  /// [_startAt]と[_endAt]の暦日が異なるか（複数日の予定かどうか）。
  /// 参加確認を日ごとに取るトグルの表示要否に使う（2026-09-02追加）。
  bool get _isMultiDay {
    final end = _endAt;
    if (end == null) return false;
    return _startAt.year != end.year ||
        _startAt.month != end.month ||
        _startAt.day != end.day;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  /// 終日トグルの切り替え。ONにする際は現在の開始・終了日時を
  /// [_preAllDayStartAt]/[_preAllDayEndAt]に退避してから日付のみに削り、
  /// OFFに戻す際は退避してあればそれをそのまま復元する（2026-09-04追加、
  /// 複数日の予定を終日にした後で元に戻せるようにするため）。
  void _setAllDay(bool value) {
    setState(() {
      if (value && !_isAllDay) {
        _preAllDayStartAt = _startAt;
        _preAllDayEndAt = _endAt;
        _hasPreAllDaySnapshot = true;
        _startAt = DateTime(_startAt.year, _startAt.month, _startAt.day);
        final end = _endAt;
        if (end != null) {
          _endAt = DateTime(end.year, end.month, end.day);
        }
      } else if (!value && _isAllDay && _hasPreAllDaySnapshot) {
        _startAt = _preAllDayStartAt!;
        _endAt = _preAllDayEndAt;
        _hasPreAllDaySnapshot = false;
        _preAllDayStartAt = null;
        _preAllDayEndAt = null;
      }
      _isAllDay = value;
    });
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

  /// 回答期限を選ぶ（2026-09-04追加）。`_pickDateTime`は`_isAllDay`が
  /// trueだと時刻をスキップして日付のみを返すが、回答期限は予定自体が
  /// 終日でも常に日時（締切の具体的な時刻）を指定できるべきのため、
  /// `_pickDateTime`は使わず直接`showDatePicker`→`showTimePicker`を呼ぶ。
  Future<void> _pickDeadline() async {
    final initial = _rsvpDeadline ?? _startAt;
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
      () => _rsvpDeadline = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
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
      final existing = widget.existingEvent;
      if (existing != null) {
        await repo.updateEvent(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          eventId: existing.eventId,
          title: title,
          description: description.isEmpty ? null : description,
          startAt: _startAt,
          endAt: _endAt,
          isAllDay: _isAllDay,
          location: location.isEmpty ? null : location,
          rsvpEnabled: _rsvpEnabled,
          rsvpPerDay: _rsvpEnabled && _isMultiDay && _rsvpPerDay,
          rsvpDeadline: _rsvpEnabled ? _rsvpDeadline : null,
        );
      } else {
        final created = await repo.createEvent(
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
          rsvpEnabled: _rsvpEnabled,
          rsvpPerDay: _rsvpEnabled && _isMultiDay && _rsvpPerDay,
          rsvpDeadline: _rsvpEnabled ? _rsvpDeadline : null,
        );
        // メッセージ画面への通知は副次的な効果であり、失敗しても予定の
        // 作成自体は成功として扱う（setRsvpのrsvpCount更新と同じ設計判断、
        // 2026-09-04追加）。
        try {
          if (widget.isDm) {
            await ref
                .read(directMessageRepositoryProvider)
                .sendCalendarEventCreatedMessage(
                  dmId: widget.conversationId,
                  roomId: widget.roomId,
                  senderId: widget.currentUserId,
                  senderRhingId: widget.currentUserRhingId,
                  eventId: created.eventId,
                  eventTitle: created.title,
                );
          } else {
            await ref
                .read(groupRepositoryProvider)
                .sendCalendarEventCreatedMessage(
                  groupId: widget.conversationId,
                  roomId: widget.roomId,
                  senderId: widget.currentUserId,
                  senderRhingId: widget.currentUserRhingId,
                  eventId: created.eventId,
                  eventTitle: created.title,
                );
          }
        } catch (e) {
          // 上記の理由により再スローしないが、原因調査のためログには残す
          // （2026-09-04追加）。
          debugPrint('[calendarEventCreatedMessage] failed: $e');
        }
      }
      if (mounted) Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final localeCode = ref.watch(appLocaleProvider).languageCode;
    final dateFormat = _isAllDay
        ? DateFormat.yMMMd(localeCode)
        : DateFormat.yMMMd(localeCode).add_Hm();
    // 回答期限は予定自体が終日でも常に時刻まで指定するため、`dateFormat`
    // （終日時は日付のみ）とは別に常に日時表示するフォーマットを使う。
    final deadlineFormat = DateFormat.yMMMd(localeCode).add_Hm();
    final isGlass =
        ProviderScope.containerOf(context).read(appUiStyleProvider) ==
        AppUiStyle.glass;

    final title = Text(
      _isEditing
          ? strings.calendarEditDialogTitle
          : strings.calendarCreateDialogTitle,
    );
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.calendarAllDayLabel),
              value: _isAllDay,
              onChanged: _setAllDay,
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
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.calendarRsvpEnabledLabel),
              value: _rsvpEnabled,
              onChanged: (value) => setState(() => _rsvpEnabled = value),
            ),
            if (_rsvpEnabled && _isMultiDay)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(strings.calendarRsvpPerDayLabel),
                value: _rsvpPerDay,
                onChanged: (value) => setState(() => _rsvpPerDay = value),
              ),
            if (_rsvpEnabled)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(strings.calendarRsvpDeadlineLabel),
                subtitle: Text(
                  _rsvpDeadline != null
                      ? deadlineFormat.format(_rsvpDeadline!)
                      : strings.calendarRsvpDeadlineNoneLabel,
                ),
                trailing: _rsvpDeadline != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: '',
                        onPressed: () =>
                            setState(() => _rsvpDeadline = null),
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
