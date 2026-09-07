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
import '../../widgets/media_viewer_screen.dart';
import '../../widgets/video_thumbnail.dart';
import '../calendar/calendar_chip.dart';
import 'poll_option_media_picker.dart';

/// 投票の詳細・投票ダイアログ（2026-09-06追加）。投票開始通知メッセージの
/// タップ時、タスクバナーのタップ時いずれからも開く唯一の導線。
/// `schedule_coordination_detail_dialog.dart`と同じ`showDialog`パターン。
Future<void> showPollDetailDialog(
  BuildContext context, {
  required bool isDm,
  required String conversationId,
  required String roomId,
  required Poll poll,
  required AppUser currentUser,
}) {
  return showDialog<void>(
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

typedef _ParticipantsData = ({
  List<String> participantIds,
  Map<String, AppUser> usersById,
});

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

  late final Future<_ParticipantsData>? _participantsFuture =
      widget.poll.anonymous ? null : _loadParticipants();

  Future<_ParticipantsData> _loadParticipants() async {
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
  /// 時点の選択肢数のまま計算して末尾キーが衝突するのを避けるため）。
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
    final confirmed = await showDialog<bool>(
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
            : AlertDialog(title: title, content: content, actions: actions);
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

                    return _OptionsList(
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
            : AlertDialog(title: title, content: content, actions: actions);
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

/// 選択肢一覧（選択チップ＋得票数＋（非匿名投票のみ）投票者一覧、
/// 2026-09-06追加）。
class _OptionsList extends StatelessWidget {
  const _OptionsList({
    required this.poll,
    required this.selectedKeys,
    required this.interactive,
    required this.onToggle,
    required this.responsesStream,
    required this.participantsFuture,
    required this.conversationId,
    required this.strings,
  });

  final Poll poll;
  final Set<String> selectedKeys;
  final bool interactive;
  final ValueChanged<String> onToggle;
  final Stream<List<PollResponse>>? responsesStream;
  final Future<_ParticipantsData>? participantsFuture;
  final String conversationId;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final optionKeys = poll.orderedOptionKeys;
    // メディアビューア（メッセージ画面と全く同じ挙動）での前後ナビゲーション
    // 対象。同じ投票内でメディア添付がある選択肢のみを、選択肢の並び順の
    // まま対象にする（2026-09-07追加）。
    final mediaOptionKeys = optionKeys
        .where((key) => poll.options[key]?.mediaUrl != null)
        .toList();

    Widget optionsColumn(
      List<PollResponse>? responses,
      _ParticipantsData? participants,
    ) {
      final respondedIds = <String>{
        if (responses != null)
          for (final r in responses) r.userId,
      };
      final noResponse = participants == null
          ? const <AppUser>[]
          : [
              for (final id in participants.participantIds)
                if (!respondedIds.contains(id)) ?participants.usersById[id],
            ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final key in optionKeys)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (poll.options[key]?.mediaUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => openMediaViewer(
                              context,
                              items: [
                                for (final k in mediaOptionKeys)
                                  MediaViewerItem(
                                    id: k,
                                    url: poll.options[k]!.mediaUrl!,
                                    contentType: poll.options[k]!.hasVideo
                                        ? 'video'
                                        : 'image',
                                  ),
                              ],
                              initialIndex: mediaOptionKeys.indexOf(key),
                            ),
                            child: poll.options[key]!.hasVideo
                                ? VideoThumbnail(
                                    url: poll.options[key]!.mediaUrl!,
                                    canLoad: videoPlaybackSupported,
                                    size: 56,
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      poll.options[key]!.mediaUrl!,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                          ),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: interactive ? () => onToggle(key) : null,
                            child: Row(
                              children: [
                                IgnorePointer(
                                  child: poll.allowMultipleChoices
                                      ? Checkbox(
                                          value: selectedKeys.contains(key),
                                          onChanged: interactive
                                              ? (_) {}
                                              : null,
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        )
                                      : RadioGroup<String>(
                                          groupValue: selectedKeys.isEmpty
                                              ? null
                                              : selectedKeys.first,
                                          onChanged: (_) {},
                                          child: Radio<String>(
                                            value: key,
                                            visualDensity:
                                                VisualDensity.compact,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${poll.options[key]?.text ?? ''} (${poll.voteCountFor(key)})',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (participants != null) ...[
            const Divider(height: 24),
            CalendarResponseGroup(
              label: strings.calendarRsvpStatusNoResponse,
              users: noResponse,
              conversationId: conversationId,
            ),
          ],
          if (responses != null && participants != null)
            for (final key in optionKeys)
              CalendarResponseGroup(
                label: poll.options[key]?.text ?? '',
                users: [
                  for (final r in responses)
                    if (r.selectedOptionKeys.contains(key))
                      ?participants.usersById[r.userId],
                ],
                conversationId: conversationId,
              ),
        ],
      );
    }

    final responsesStream = this.responsesStream;
    final participantsFuture = this.participantsFuture;
    if (responsesStream == null || participantsFuture == null) {
      // 匿名投票: 得票数のみ表示し、誰が投票したかは一切問い合わせない。
      return optionsColumn(null, null);
    }
    return FutureBuilder<_ParticipantsData>(
      future: participantsFuture,
      builder: (context, participantsSnapshot) {
        final participants = participantsSnapshot.data;
        if (participants == null) {
          return optionsColumn(null, null);
        }
        return StreamBuilder<List<PollResponse>>(
          stream: responsesStream,
          builder: (context, responseSnapshot) {
            return optionsColumn(
              responseSnapshot.data ?? const [],
              participants,
            );
          },
        );
      },
    );
  }
}
