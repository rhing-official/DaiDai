import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/poll.dart';
import '../../models/poll_response.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/poll_repository.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/destructive_label.dart';
import '../../widgets/glass/glass_dialog.dart';
import 'poll_option_media_picker.dart';
import 'poll_options_list.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/app_dialog.dart';

/// 投票の詳細・投票ダイアログ（2026-09-06追加）。投票開始通知メッセージの
/// タップ時、タスクバナーのタップ時いずれからも開く唯一の導線。
/// `schedule_coordination_detail_dialog.dart`と同じ`showAppDialog`パターン。
Future<void> showPollDetailDialog(
  BuildContext context, {
  required bool isDm,
  required String conversationId,
  required String roomId,
  required Poll poll,
  required AppUser currentUser,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (_) => _PollDetailDialog(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      poll: poll,
      currentUser: currentUser,
    ),
  );
}

class _PollDetailDialog extends ConsumerStatefulWidget {
  const _PollDetailDialog({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.poll,
    required this.currentUser,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final Poll poll;
  final AppUser currentUser;

  @override
  ConsumerState<_PollDetailDialog> createState() => _PollDetailDialogState();
}

class _PollDetailDialogState extends ConsumerState<_PollDetailDialog> {
  final Set<String> _selectedKeys = {};
  bool _initializedFromExisting = false;
  bool _saving = false;
  bool _deleting = false;
  bool _addingOption = false;

  final _newOptionController = TextEditingController();
  Uint8List? _newOptionMediaBytes;
  String? _newOptionMediaFileName;

  /// 'image' | 'video' | null（未選択）。
  String? _newOptionMediaType;

  late final Stream<Poll?> _pollStream = ref
      .read(pollRepositoryProvider)
      .watchPoll(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
        pollId: widget.poll.pollId,
      );

  late final Stream<PollResponse?> _myResponseStream = ref
      .read(pollRepositoryProvider)
      .watchMyResponse(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
        pollId: widget.poll.pollId,
        userId: widget.currentUser.userId,
      );

  late final Stream<List<PollResponse>>? _responsesStream =
      widget.poll.anonymous
      ? null
      : ref
            .read(pollRepositoryProvider)
            .watchResponses(
              isDm: widget.isDm,
              conversationId: widget.conversationId,
              roomId: widget.roomId,
              pollId: widget.poll.pollId,
            );

  late final Future<PollParticipantsData>? _participantsFuture =
      widget.poll.anonymous ? null : _loadParticipants();

  Future<PollParticipantsData> _loadParticipants() async {
    final ids = await ref
        .read(pollRepositoryProvider)
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
    _newOptionController.dispose();
    super.dispose();
  }

  void _initFromExisting(PollResponse? response) {
    if (_initializedFromExisting || response == null) return;
    _initializedFromExisting = true;
    _selectedKeys.addAll(response.selectedOptionKeys);
  }

  void _toggleOption(String key, Poll poll) {
    setState(() {
      if (poll.allowMultipleChoices) {
        if (_selectedKeys.contains(key)) {
          _selectedKeys.remove(key);
        } else {
          _selectedKeys.add(key);
        }
      } else {
        _selectedKeys
          ..clear()
          ..add(key);
      }
    });
  }

  Future<void> _vote() async {
    if (_selectedKeys.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(pollRepositoryProvider)
          .castVote(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            pollId: widget.poll.pollId,
            userId: widget.currentUser.userId,
            selectedOptionKeys: _selectedKeys.toList(),
          );
    } catch (e) {
      if (mounted) showAutoDismissBanner(context, message: '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickNewOptionMedia({required bool video}) async {
    final picker = ImagePicker();
    final picked = video
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _newOptionMediaBytes = bytes;
      _newOptionMediaFileName = picked.name;
      _newOptionMediaType = video ? 'video' : 'image';
    });
  }

  /// 選択肢を末尾に1件追加する。呼び出し直前に最新のPollを取得し直して
  /// [PollRepository.addOption]の[currentOptionCount]を算出する（複数の
  /// 参加者がほぼ同時に選択肢を追加した場合でも、この詳細ダイアログを開いた
  /// 時点の選択肢数のまま計算して末尾キーが衝突するのを避ける為）。
  Future<void> _addOption() async {
    final text = _newOptionController.text.trim();
    if (text.isEmpty) return;
    setState(() => _addingOption = true);
    try {
      final latest = await ref
          .read(pollRepositoryProvider)
          .getPoll(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            pollId: widget.poll.pollId,
          );
      final currentCount = latest?.options.length ?? widget.poll.options.length;
      await ref
          .read(pollRepositoryProvider)
          .addOption(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            pollId: widget.poll.pollId,
            option: PollOptionDraft(
              text: text,
              mediaBytes: _newOptionMediaBytes,
              mediaFileName: _newOptionMediaFileName,
              mediaType: _newOptionMediaType,
            ),
            currentOptionCount: currentCount,
          );
      _newOptionController.clear();
      if (mounted) {
        setState(() {
          _newOptionMediaBytes = null;
          _newOptionMediaFileName = null;
          _newOptionMediaType = null;
        });
      }
    } catch (e) {
      if (mounted) showAutoDismissBanner(context, message: '$e');
    } finally {
      if (mounted) setState(() => _addingOption = false);
    }
  }

  Future<void> _delete() async {
    final strings = ref.read(appStringsProvider);
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) {
        final title = Text(strings.pollDeleteConfirmTitle);
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
            : KeyboardAlertDialog(
                title: title,
                content: content,
                actions: actions,
              );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref
          .read(pollRepositoryProvider)
          .deletePoll(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            pollId: widget.poll.pollId,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showAutoDismissBanner(context, message: '$e');
        setState(() => _deleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final localeCode = ref.watch(appLocaleProvider).languageCode;
    final deadlineFormat = DateFormat.yMMMd(localeCode).add_Hm();

    return StreamBuilder<Poll?>(
      stream: _pollStream,
      initialData: widget.poll,
      builder: (context, pollSnapshot) {
        final poll = pollSnapshot.data ?? widget.poll;
        final isCreator = widget.currentUser.userId == poll.createdBy;
        final deadline = poll.deadline?.toDate();
        final closed = poll.isClosed;

        final title = Text(
          poll.question,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );

        final content = SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (deadline != null)
                  Text(
                    '${strings.calendarRsvpDeadlineLabel}: '
                    '${deadlineFormat.format(deadline)}'
                    '${closed ? strings.calendarRsvpDeadlinePassedLabel : ''}',
                    style: TextStyle(
                      color: closed
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                if (closed)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      strings.calendarRsvpDeadlinePassedNotice,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (poll.anonymous)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      strings.pollAnonymousNotice,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const Divider(height: 24),
                StreamBuilder<PollResponse?>(
                  stream: _myResponseStream,
                  builder: (context, responseSnapshot) {
                    final myResponse = responseSnapshot.data;
                    _initFromExisting(myResponse);

                    return PollOptionsList(
                      poll: poll,
                      selectedKeys: _selectedKeys,
                      interactive: !closed,
                      onToggle: (key) => _toggleOption(key, poll),
                      responsesStream: _responsesStream,
                      participantsFuture: _participantsFuture,
                      conversationId: widget.conversationId,
                      strings: strings,
                    );
                  },
                ),
                if (poll.allowAddingOptions && !closed) ...[
                  const Divider(height: 24),
                  Row(
                    children: [
                      PollOptionMediaPickerButton(
                        strings: strings,
                        mediaBytes: _newOptionMediaBytes,
                        mediaType: _newOptionMediaType,
                        enabled: !_addingOption,
                        onPick: (video) => _pickNewOptionMedia(video: video),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _newOptionController,
                          enabled: !_addingOption,
                          decoration: InputDecoration(
                            hintText: strings.pollOptionFieldHint,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '',
                        icon: const Icon(Icons.add),
                        onPressed: _addingOption ? null : _addOption,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );

        final actions = [
          if (isCreator)
            TextButton(
              onPressed: _deleting ? null : _delete,
              child: IntrinsicWidth(
                child: DestructiveLabel(strings.pollDeleteAction),
              ),
            ),
          StreamBuilder<PollResponse?>(
            stream: _myResponseStream,
            builder: (context, responseSnapshot) {
              final hasVoted = responseSnapshot.data != null;
              return FilledButton(
                onPressed: (_saving || closed || _selectedKeys.isEmpty)
                    ? null
                    : _vote,
                child: Text(
                  hasVoted
                      ? strings.pollChangeVoteButton
                      : strings.pollVoteButton,
                ),
              );
            },
          ),
        ];

        final dialog = isGlass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : KeyboardAlertDialog(
                title: title,
                content: content,
                actions: actions,
              );
        // 選択肢が複数並ぶため、既定の確認ダイアログ幅(maxWidth: 400)より
        // 広げる（schedule_coordination_detail_dialog.dartと同じ理由）。
        final ambientTheme = Theme.of(context);
        return Theme(
          data: ambientTheme.copyWith(
            dialogTheme: ambientTheme.dialogTheme.copyWith(
              constraints: const BoxConstraints(maxWidth: 480),
            ),
          ),
          child: dialog,
        );
      },
    );
  }
}
