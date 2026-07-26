import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/friend_request.dart';
import '../../providers/repository_providers.dart';

/// 広場（グループ）のメッセージ画面・メンバー一覧から、相手のプロフィール
/// カード（適用中の工房カード）を見られるようにするダイアログ。友達でなければ
/// その場で友達申請を送れる（相手から既に申請が届いていれば、送信すると
/// そのまま承認扱いになる。[FriendRepository.sendRequest]の既存の挙動）。
///
/// 一対（DM）の相手は仕組み上必ず既に友達のため、このダイアログは広場側からの
/// 導線でのみ使う想定。
class UserProfileCardDialog extends ConsumerStatefulWidget {
  const UserProfileCardDialog({
    required this.currentUser,
    required this.user,
    super.key,
  });

  final AppUser currentUser;
  final AppUser user;

  static Future<void> show(
    BuildContext context, {
    required AppUser currentUser,
    required AppUser user,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) =>
          UserProfileCardDialog(currentUser: currentUser, user: user),
    );
  }

  @override
  ConsumerState<UserProfileCardDialog> createState() =>
      _UserProfileCardDialogState();
}

class _UserProfileCardDialogState extends ConsumerState<UserProfileCardDialog> {
  late Future<FriendRequest?> _requestFuture;
  bool _sending = false;

  bool get _isSelf => widget.currentUser.userId == widget.user.userId;

  @override
  void initState() {
    super.initState();
    _requestFuture = _fetchRequest();
  }

  Future<FriendRequest?> _fetchRequest() {
    return ref
        .read(friendRepositoryProvider)
        .getRequest(widget.currentUser.userId, widget.user.userId);
  }

  Future<void> _sendRequest() async {
    setState(() => _sending = true);
    try {
      await ref.read(friendRepositoryProvider).sendRequest(
            from: widget.currentUser,
            to: widget.user,
          );
      if (!mounted) return;
      setState(() => _requestFuture = _fetchRequest());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final user = widget.user;
    final card = user.activeProfileCard;
    final name = (card != null && card.name.isNotEmpty)
        ? card.name
        : (user.effectiveNickname?.text.isNotEmpty ?? false)
            ? user.effectiveNickname!.text
            : '@${user.rhingId}';
    final iconUrl = user.effectiveIcon?.url;
    final backgroundUrl = user.effectiveBackgroundImage?.url;
    final statusMessage = user.effectiveStatusMessage?.text;
    final snsLinks = user.effectiveSnsLinks;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (backgroundUrl != null)
                      Image.network(backgroundUrl, fit: BoxFit.cover)
                    else
                      Container(color: colorScheme.surfaceContainerHighest),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 12,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundImage:
                                iconUrl != null ? NetworkImage(iconUrl) : null,
                            child: iconUrl == null
                                ? Text(
                                    user.rhingId.isNotEmpty
                                        ? user.rhingId[0].toUpperCase()
                                        : '?',
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                shadows: [Shadow(blurRadius: 6)],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '@${user.rhingId}',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  if (statusMessage != null && statusMessage.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(statusMessage),
                  ],
                  if (snsLinks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final link in snsLinks)
                      Text(
                        link.url,
                        style: TextStyle(color: colorScheme.primary),
                      ),
                  ],
                  if (!_isSelf) ...[
                    const SizedBox(height: 16),
                    _friendActionArea(strings, colorScheme),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.userProfileCardClose),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _friendActionArea(Strings strings, ColorScheme colorScheme) {
    return FutureBuilder<FriendRequest?>(
      future: _requestFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 36,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final request = snapshot.data;

        if (request?.status == FriendRequestStatus.accepted) {
          return Text(
            strings.userProfileCardAlreadyFriend,
            style: TextStyle(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          );
        }

        if (request?.status == FriendRequestStatus.pending) {
          final isOutgoing = request!.fromUserId == widget.currentUser.userId;
          if (isOutgoing) {
            return Text(strings.userProfileCardRequestPending);
          }
          // 相手からの申請が既に届いている場合、送信すると
          // FriendRepository.sendRequestの既存の挙動でそのまま承認される。
          return SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sending ? null : _sendRequest,
              child: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(strings.userProfileCardAcceptRequest),
            ),
          );
        }

        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _sending ? null : _sendRequest,
            child: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(strings.userProfileCardSendRequest),
          ),
        );
      },
    );
  }
}
