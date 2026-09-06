import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/poll_repository.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../calendar/calendar_chip.dart';
import 'poll_option_media_picker.dart';

/// 投票の作成モード（2026-09-06追加）。「選択肢」は自由記述の選択肢
/// （画像添付・複数選択可・選択肢の追加を許可に対応）、「二択」は選択肢入力を
/// 省き固定で○/×の2択にする（旧名「○×」、モード名としては何を指すか
/// 分かりにくいとのユーザー指摘によりモード名のみ改名。実際の投票の
/// 選択肢の文言は引き続き「○」「×」のまま）。データ形状はどちらも同じ
/// [Poll.options]（2件以上のMap）で、UI側でのみ分岐する。
enum _PollCreateMode { options, maruBatsu }

/// 投票の作成ダイアログ（2026-09-06追加）。`schedule_coordination_form_dialog.dart`
/// と同じ`showDialog`パターン。保存されたら`true`、キャンセルされたら
/// `false`を返す。
Future<bool> showPollFormDialog(
  BuildContext context, {
  required bool isDm,
  required String conversationId,
  required String roomId,
  required String currentUserId,
  required String currentUserRhingId,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _PollFormDialog(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      currentUserId: currentUserId,
      currentUserRhingId: currentUserRhingId,
    ),
  );
  return saved ?? false;
}

class _OptionDraft {
  _OptionDraft()
    : controller = TextEditingController(),
      focusNode = FocusNode();

  final TextEditingController controller;
  final FocusNode focusNode;
  Uint8List? mediaBytes;
  String? mediaFileName;

  /// 'image' | 'video' | null（添付なし）。
  String? mediaType;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _PollFormDialog extends ConsumerStatefulWidget {
  const _PollFormDialog({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.currentUserId,
    required this.currentUserRhingId,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final String currentUserId;
  final String currentUserRhingId;

  @override
  ConsumerState<_PollFormDialog> createState() => _PollFormDialogState();
}

class _PollFormDialogState extends ConsumerState<_PollFormDialog> {
  final _questionController = TextEditingController();
  final List<_OptionDraft> _options = [_OptionDraft(), _OptionDraft()];
  _PollCreateMode _mode = _PollCreateMode.options;
  DateTime? _deadline;
  bool _allowMultipleChoices = false;
  bool _anonymous = false;
  bool _allowAddingOptions = false;
  bool _saving = false;

  @override
  void dispose() {
    _questionController.dispose();
    for (final option in _options) {
      option.dispose();
    }
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

  Future<void> _pickDeadline() async {
    final initial = _deadline ?? DateTime.now();
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

  void _addOption() => setState(() => _options.add(_OptionDraft()));

  // 選択肢の入力中にEnterを押したときの挙動（2026-09-06追加）: 次の選択肢が
  // あればそこへフォーカスを移し、最後の選択肢であれば新規追加してそちらへ
  // フォーカスする（Googleフォーム等と同じ、入力を止めずに済む挙動）。
  void _moveToNextOptionOrAdd(int index) {
    if (index + 1 < _options.length) {
      _options[index + 1].focusNode.requestFocus();
      return;
    }
    final newOption = _OptionDraft();
    setState(() => _options.add(newOption));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      newOption.focusNode.requestFocus();
    });
  }

  void _removeOption(int index) {
    if (_options.length <= 2) return;
    setState(() => _options.removeAt(index).dispose());
  }

  Future<void> _pickOptionMedia(
    _OptionDraft option, {
    required bool video,
  }) async {
    final picker = ImagePicker();
    final picked = video
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      option.mediaBytes = bytes;
      option.mediaFileName = picked.name;
      option.mediaType = video ? 'video' : 'image';
    });
  }

  Future<void> _save() async {
    final strings = ref.read(appStringsProvider);
    final question = _questionController.text.trim();
    if (question.isEmpty) return;

    final List<PollOptionDraft> drafts;
    if (_mode == _PollCreateMode.maruBatsu) {
      drafts = const [PollOptionDraft(text: '○'), PollOptionDraft(text: '×')];
    } else {
      drafts = [
        for (final option in _options)
          if (option.controller.text.trim().isNotEmpty)
            PollOptionDraft(
              text: option.controller.text.trim(),
              mediaBytes: option.mediaBytes,
              mediaFileName: option.mediaFileName,
              mediaType: option.mediaType,
            ),
      ];
      if (drafts.length < 2) {
        showAutoDismissBanner(
          context,
          message: strings.pollMinimumOptionsError,
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final poll = await ref
          .read(pollRepositoryProvider)
          .createPoll(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            question: question,
            options: drafts,
            createdBy: widget.currentUserId,
            deadline: _deadline,
            allowMultipleChoices:
                _mode == _PollCreateMode.options && _allowMultipleChoices,
            anonymous: _anonymous,
            allowAddingOptions:
                _mode == _PollCreateMode.options && _allowAddingOptions,
          );
      // メッセージ画面への通知は副次的な効果であり、失敗しても投票の作成
      // 自体は成功として扱う（schedule_coordination_form_dialog.dartの
      // sendScheduleCoordinationCreatedMessageと同じ設計判断）。
      try {
        if (widget.isDm) {
          await ref
              .read(directMessageRepositoryProvider)
              .sendPollCreatedMessage(
                dmId: widget.conversationId,
                roomId: widget.roomId,
                senderId: widget.currentUserId,
                senderRhingId: widget.currentUserRhingId,
                pollId: poll.pollId,
                pollQuestion: poll.question,
              );
        } else {
          await ref
              .read(groupRepositoryProvider)
              .sendPollCreatedMessage(
                groupId: widget.conversationId,
                roomId: widget.roomId,
                senderId: widget.currentUserId,
                senderRhingId: widget.currentUserRhingId,
                pollId: poll.pollId,
                pollQuestion: poll.question,
              );
        }
      } catch (e) {
        debugPrint('[pollCreatedMessage] failed: $e');
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showAutoDismissBanner(context, message: '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final localeCode = ref.watch(appLocaleProvider).languageCode;
    final deadlineFormat = DateFormat.yMMMd(localeCode).add_Hm();
    final isGlass =
        ProviderScope.containerOf(context).read(appUiStyleProvider) ==
        AppUiStyle.glass;

    final title = Text(strings.pollCreateDialogTitle);
    final content = SizedBox(
      width: 380,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              children: [
                calendarChoiceChip(
                  context,
                  label: strings.pollModeOptionsLabel,
                  selected: _mode == _PollCreateMode.options,
                  onSelected: (_) =>
                      setState(() => _mode = _PollCreateMode.options),
                ),
                calendarChoiceChip(
                  context,
                  label: strings.pollModeMaruBatsuLabel,
                  selected: _mode == _PollCreateMode.maruBatsu,
                  onSelected: (_) =>
                      setState(() => _mode = _PollCreateMode.maruBatsu),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _questionController,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: strings.pollQuestionFieldHint,
              ),
            ),
            if (_mode == _PollCreateMode.options) ...[
              const SizedBox(height: 12),
              for (var i = 0; i < _options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      PollOptionMediaPickerButton(
                        strings: strings,
                        mediaBytes: _options[i].mediaBytes,
                        mediaType: _options[i].mediaType,
                        onPick: (video) =>
                            _pickOptionMedia(_options[i], video: video),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _options[i].controller,
                          focusNode: _options[i].focusNode,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _moveToNextOptionOrAdd(i),
                          decoration: InputDecoration(
                            hintText: strings.pollOptionFieldHint,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _options.length > 2
                            ? () => _removeOption(i)
                            : null,
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add),
                label: Text(strings.pollAddOptionButton),
              ),
            ],
            const Divider(height: 24),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(strings.pollSetDeadlineCheckboxLabel),
              subtitle: _deadline != null
                  ? Text(deadlineFormat.format(_deadline!))
                  : null,
              value: _deadline != null,
              onChanged: (checked) {
                if (checked == true) {
                  _pickDeadline();
                } else {
                  setState(() => _deadline = null);
                }
              },
            ),
            if (_mode == _PollCreateMode.options) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(strings.pollAllowMultipleChoicesCheckboxLabel),
                value: _allowMultipleChoices,
                onChanged: (checked) =>
                    setState(() => _allowMultipleChoices = checked ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(strings.pollAllowAddingOptionsCheckboxLabel),
                value: _allowAddingOptions,
                onChanged: (checked) =>
                    setState(() => _allowAddingOptions = checked ?? false),
              ),
            ],
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(strings.pollAnonymousCheckboxLabel),
              value: _anonymous,
              onChanged: (checked) =>
                  setState(() => _anonymous = checked ?? false),
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
