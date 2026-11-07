import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/poll.dart';
import '../../models/poll_response.dart';
import '../../widgets/media_viewer_screen.dart';
import '../../widgets/toggles/app_checkbox.dart';
import '../../widgets/video_thumbnail.dart';
import '../calendar/calendar_chip.dart';

typedef PollParticipantsData = ({
  List<String> participantIds,
  Map<String, AppUser> usersById,
});

/// 選択肢一覧（選択チップ＋得票数＋（非匿名投票のみ）投票者一覧、
/// 2026-09-06追加）。[responsesStream]/[participantsFuture]がnullなら得票数のみ
/// （匿名投票、およびメッセージ内の埋め込みカード、2026-11-07）。
class PollOptionsList extends StatelessWidget {
  const PollOptionsList({
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
  final Future<PollParticipantsData>? participantsFuture;
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
      PollParticipantsData? participants,
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
                                      ? AppCheckbox(
                                          value: selectedKeys.contains(key),
                                          onChanged: interactive
                                              ? (_) {}
                                              : null,
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
    return FutureBuilder<PollParticipantsData>(
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
