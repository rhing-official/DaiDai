import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers/conversation_call_providers.dart';
import 'call_avatar.dart';

/// 通話に入っている人のアイコン（重ねて最大[maxAvatars]人、超えたら「+N」）と呼び名の文
/// （1人「A」・2人「A・B」・3人以上「Aほか2人」）（2026-11-17）。広場の通話バナー・語らい一覧の
/// 標で使う。幅が[namesMinWidth]未満なら呼び名を省いてアイコンだけにする。文字色は[color]
/// （面と反対の色を呼び出し側が渡す）。[conversationId]は一対のdmId・広場のgroupId。
class CallParticipantsStrip extends ConsumerWidget {
  const CallParticipantsStrip({
    required this.users,
    required this.conversationId,
    required this.color,
    this.avatarRadius = 12,
    this.maxAvatars = 4,
    this.showNames = true,
    this.namesMinWidth = 200,
    super.key,
  });

  final List<CallPresenceUser> users;
  final String conversationId;
  final Color color;
  final double avatarRadius;
  final int maxAvatars;
  final bool showNames;
  final double namesMinWidth;

  /// 呼び名の文。人数に応じて組み立てる。
  static String namesLabel(Strings strings, List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    if (names.length == 2) {
      return strings.callPresenceNamesTwo(names[0], names[1]);
    }
    return strings.callPresenceNamesMore(names.first, names.length - 1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (users.isEmpty) return const SizedBox.shrink();
    final strings = ref.watch(appStringsProvider);
    final shown = users.take(maxAvatars).toList();
    final extra = users.length - shown.length;
    final overlap = avatarRadius * 0.6;
    final avatars = SizedBox(
      height: avatarRadius * 2,
      width:
          avatarRadius * 2 + (shown.length - 1) * (avatarRadius * 2 - overlap),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (avatarRadius * 2 - overlap),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
                child: CallParticipantAvatar(
                  userId: shown[i].userId,
                  rhingSeed: shown[i].rhingSeed,
                  conversationId: conversationId,
                  radius: avatarRadius,
                ),
              ),
            ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final canShowNames = showNames && constraints.maxWidth >= namesMinWidth;
        final names = canShowNames
            ? [
                for (final u in users)
                  callParticipantDisplayName(
                    ref,
                    userId: u.userId,
                    rhingSeed: u.rhingSeed,
                    conversationId: conversationId,
                  ),
              ]
            : const <String>[];
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            avatars,
            if (extra > 0) ...[
              const SizedBox(width: 4),
              Text('+$extra', style: TextStyle(color: color, fontSize: 12)),
            ],
            if (canShowNames) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  namesLabel(strings, names),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
