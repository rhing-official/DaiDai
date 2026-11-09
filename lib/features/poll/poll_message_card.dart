import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/poll.dart';
import '../../models/poll_response.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/poll_embed.dart';
import '../../widgets/media_viewer_screen.dart';
import '../../widgets/video_thumbnail.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/toggles/app_checkbox.dart';
import '../../widgets/toggles/app_radio.dart';
import 'poll_vote_button.dart';

/// 直近に受け取った投票・自分の回答の写し（メモリのみ、2026-11-08）。語らいを
/// 開き直した時、購読の初回の値が届くまで通知カード（背が高い）を出してから埋め込み
/// カードへ差し替わると、内容全体が上下にずれて見えた。前回の値を最初のフレームから
/// 使えば、2回目以降は差し替わらない。更新は購読が届き次第すぐ反映する。
final _pollCache = <String, Poll>{};
final _responseCache = <String, PollResponse?>{};

/// 投票開始通知メッセージ（`contentType: 'pollCreated'`）の中に、選択肢を
/// そのまま出してその場で投票できる埋め込みカード（2026-11-07、
/// `文書/投票埋め込み.md`）。
///
/// 画像・動画付き、または選択肢が多い投票（[shouldCollapsePoll]）、読み込み中、
/// 投票が取得できない（削除済みなど）場合は、従来の小さい通知カード[fallback]を
/// 出す（タップでダイアログを開く動きは従来どおり）。枠・幅は[frame]に任せ、
/// 通知カードと同じ見た目（劇画・ガラス・版画・フラット）を保つ。
class PollMessageCard extends ConsumerStatefulWidget {
  const PollMessageCard({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.pollId,
    required this.currentUserId,
    required this.foreground,
    required this.fallback,
    required this.frame,
    required this.onOpen,
    super.key,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final String pollId;
  final String currentUserId;

  /// カード内の文字色（劇画は吹き出しに合わせた単色、それ以外はテーマの文字色）。
  final Color foreground;

  /// 折りたたむ時・読み込み中の従来の通知カード。
  final Widget fallback;

  /// 埋め込みの中身を、通知カードと同じ枠で包む。
  final Widget Function(Widget content) frame;

  /// 詳細ダイアログを開く（カードの選択肢・ボタン以外をタップした時）。
  final VoidCallback onOpen;

  @override
  ConsumerState<PollMessageCard> createState() => _PollMessageCardState();
}

class _PollMessageCardState extends ConsumerState<PollMessageCard> {
  final Set<String> _selectedKeys = {};
  bool _initializedFromExisting = false;
  bool _saving = false;

  String get _cacheKey =>
      '${widget.isDm}/${widget.conversationId}/${widget.roomId}/${widget.pollId}/${widget.currentUserId}';

  late final Stream<Poll?> _pollStream = ref
      .read(pollRepositoryProvider)
      .watchPoll(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
        pollId: widget.pollId,
      )
      .map((poll) {
        if (poll == null) {
          _pollCache.remove(_cacheKey);
        } else {
          _pollCache[_cacheKey] = poll;
        }
        return poll;
      });

  late final Stream<PollResponse?> _myResponseStream = ref
      .read(pollRepositoryProvider)
      .watchMyResponse(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
        pollId: widget.pollId,
        userId: widget.currentUserId,
      )
      .map((response) {
        _responseCache[_cacheKey] = response;
        return response;
      });

  void _initFromExisting(PollResponse? response) {
    if (_initializedFromExisting || response == null) return;
    _initializedFromExisting = true;
    _selectedKeys.addAll(response.selectedOptionKeys);
  }

  void _toggleOption(String key, Poll poll) {
    setState(() {
      if (poll.allowMultipleChoices) {
        if (!_selectedKeys.remove(key)) _selectedKeys.add(key);
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
            pollId: widget.pollId,
            userId: widget.currentUserId,
            selectedOptionKeys: _selectedKeys.toList(),
          );
    } catch (e) {
      if (mounted) showAutoDismissBanner(context, message: '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final foreground = widget.foreground;

    return StreamBuilder<Poll?>(
      stream: _pollStream,
      initialData: _pollCache[_cacheKey],
      builder: (context, pollSnapshot) {
        final poll = pollSnapshot.data;
        if (poll == null || shouldCollapsePoll(poll)) return widget.fallback;
        final closed = poll.isClosed;

        final content = DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                poll.question,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: foreground,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                poll.allowMultipleChoices
                    ? strings.pollMultipleChoiceHint
                    : strings.pollSingleChoiceHint,
                style: TextStyle(
                  fontSize: 12,
                  color: foreground.withValues(alpha: 0.75),
                ),
              ),
              if (poll.anonymous)
                Text(
                  strings.pollAnonymousNotice,
                  style: TextStyle(
                    fontSize: 12,
                    color: foreground.withValues(alpha: 0.75),
                  ),
                ),
              const SizedBox(height: 10),
              StreamBuilder<PollResponse?>(
                stream: _myResponseStream,
                initialData: _responseCache[_cacheKey],
                builder: (context, responseSnapshot) {
                  final myResponse = responseSnapshot.data;
                  _initFromExisting(myResponse);
                  final deadline = poll.deadline?.toDate();
                  final meta = [
                    strings.pollResponseCountLabel(poll.responseCount),
                    if (closed)
                      strings.pollClosedBadgeLabel
                    else if (deadline != null)
                      strings.pollRemainingTimeLabel(
                        deadline.difference(DateTime.now()),
                      ),
                  ].join(' · ');
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final key in poll.orderedOptionKeys)
                        _optionRow(
                          poll,
                          key,
                          interactive: !closed,
                          isGekiga: isGekiga,
                          foreground: foreground,
                        ),
                      const SizedBox(height: 6),
                      // 回答数・残り時間（左）と投票ボタン（右、Discord風）。
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              meta,
                              style: TextStyle(
                                fontSize: 12,
                                color: foreground.withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                          PollVoteButton(
                            isGekiga: isGekiga,
                            foreground: foreground,
                            onPressed:
                                (_saving || closed || _selectedKeys.isEmpty)
                                ? null
                                : _vote,
                            label: myResponse != null
                                ? strings.pollChangeVoteButton
                                : strings.pollVoteButton,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
        // 選択肢・投票ボタン以外の場所（質問・余白・回答数など）をタップすると
        // 詳細ダイアログを開く（選択肢の帯とボタンは自分のタップを先に処理する）。
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen,
          child: widget.frame(content),
        );
      },
    );
  }

  /// 選択肢1行（横いっぱいの帯、名前を左に・得票数と選択の印を右に、Discord風）。
  Widget _optionRow(
    Poll poll,
    String key, {
    required bool interactive,
    required bool isGekiga,
    required Color foreground,
  }) {
    final selected = _selectedKeys.contains(key);
    final radius = BorderRadius.circular(10);
    // 劇画の吹き出しは単色（黒地か白地）なので、選択の印はこの単色に合わせて描く
    // （2026-11-08、以前は標準の`Radio`で、劇画では選んでも変化が見えなかった）。
    // チェックボックスの地の色は、文字色の反対。
    final gekigaBackground = foreground == GekigaColors.panel
        ? GekigaColors.onPanel
        : GekigaColors.panel;
    final Widget marker = IgnorePointer(
      child: poll.allowMultipleChoices
          ? AppCheckbox(
              value: selected,
              onChanged: interactive ? (_) {} : null,
              foreground: isGekiga ? foreground : null,
              background: isGekiga ? gekigaBackground : null,
            )
          : AppRadioMark(
              selected: selected,
              enabled: interactive,
              color: isGekiga ? foreground : null,
            ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isGekiga
            ? Colors.transparent
            : foreground.withValues(alpha: 0.07),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: isGekiga ? BorderSide(color: foreground) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: interactive ? () => _toggleOption(key, poll) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // 画像・動画付きの選択肢は、左にサムネイルを出す。タップで拡大表示
                // （ダイアログと同じ`openMediaViewer`で、メディア付きの選択肢を巡れる）。
                if (poll.options[key]?.mediaUrl != null) ...[
                  _mediaThumbnail(poll, key),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    poll.options[key]?.text ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: foreground,
                    ),
                  ),
                ),
                Text(
                  '${poll.voteCountFor(key)}',
                  style: TextStyle(color: foreground.withValues(alpha: 0.75)),
                ),
                const SizedBox(width: 8),
                marker,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 選択肢の画像・動画のサムネイル（2026-11-08）。タップで拡大表示。
  Widget _mediaThumbnail(Poll poll, String key) {
    final option = poll.options[key]!;
    final mediaKeys = [
      for (final k in poll.orderedOptionKeys)
        if (poll.options[k]?.mediaUrl != null) k,
    ];
    return GestureDetector(
      onTap: () => openMediaViewer(
        context,
        items: [
          for (final k in mediaKeys)
            MediaViewerItem(
              id: k,
              url: poll.options[k]!.mediaUrl!,
              contentType: poll.options[k]!.hasVideo ? 'video' : 'image',
            ),
        ],
        initialIndex: mediaKeys.indexOf(key),
      ),
      child: option.hasVideo
          ? VideoThumbnail(
              url: option.mediaUrl!,
              canLoad: videoPlaybackSupported,
              size: 48,
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                option.mediaUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const SizedBox(width: 48, height: 48),
              ),
            ),
    );
  }
}
