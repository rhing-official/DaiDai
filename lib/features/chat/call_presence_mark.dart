import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers/conversation_call_providers.dart';
import '../call/active_call_session.dart';
import '../call/pinned_call_overlay.dart' show reopenActiveCall;

/// 語らい一覧の箱・寄合一覧・寄合タブに出す「通話中」の標（2026-11-17）。通話中の電話/
/// ビデオのアイコンと、入っている人数（取得できている間だけ）。通話が無ければ何も出さない。
/// [conversationId]は一対のdmId・広場のgroupId。[label]を付けると文言も出す（寄合一覧用）。
class CallPresenceMark extends ConsumerWidget {
  const CallPresenceMark({
    required this.conversationId,
    required this.color,
    this.label = false,
    this.size = 16,
    this.roomId,
    this.unplacedAmong,
    this.tappable = true,
    super.key,
  });

  final String conversationId;

  /// 指定すると、通話を始めた寄合がこの寄合の時だけ出す（寄合のブロック用、2026-11-18）。
  final String? roomId;

  /// 指定すると、通話を始めた寄合がこの一覧に無い（不明を含む）時だけ出す（寄合一覧の上部用、
  /// 2026-11-18）。通話を始めた寄合のブロックに標が出るため、そちらに出る時は出さない。
  final Set<String>? unplacedAmong;

  /// 自分が参加中の通話の標をタップして通話画面へ戻れるようにするか。
  final bool tappable;
  final Color color;
  final bool label;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presence = ref.watch(conversationCallProvider(conversationId));
    if (presence == null) return const SizedBox.shrink();
    if (roomId != null && presence.roomId != roomId) {
      return const SizedBox.shrink();
    }
    if (unplacedAmong != null && unplacedAmong!.contains(presence.roomId)) {
      return const SizedBox.shrink();
    }
    final strings = ref.watch(appStringsProvider);
    final count = presence.users.length;
    final session = ref.watch(activeCallSessionProvider);
    // 自分が参加中の通話なら、標のタップで通話画面へ戻る（ミニ表示を出さない設定でも戻れる、
    // 2026-11-18）。
    final canReopen =
        tappable && presence.isMine && session != null && !session.hasEnded;
    final mark = Tooltip(
      message: strings.callPresenceChipLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            presence.isVideo ? Icons.videocam : Icons.call,
            size: size,
            color: color,
          ),
          if (count > 0) ...[
            const SizedBox(width: 2),
            Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: size - 4,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          if (label) ...[
            const SizedBox(width: 4),
            Text(
              strings.callPresenceChipLabel,
              style: TextStyle(color: color, fontSize: size - 3),
            ),
          ],
        ],
      ),
    );
    if (!canReopen) return mark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => reopenActiveCall(ref.read, session),
      child: mark,
    );
  }
}

/// 寄合タブの下に出す、通話中の細い帯（2026-11-17）。通話は広場（一対）単位で、特定の寄合には
/// 属さないため、タブのどれにも付けず、バーとは別に1行で出す。通話が無ければ高さ0。
class CallPresenceBar extends ConsumerWidget {
  const CallPresenceBar({
    required this.conversationId,
    this.roomIds,
    super.key,
  });

  final String conversationId;

  /// 寄合タブに並ぶ寄合のid。通話を始めた寄合がここに含まれる時は、そのタブに標が出るため
  /// 帯は出さない（2026-11-18）。
  final Set<String>? roomIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presence = ref.watch(conversationCallProvider(conversationId));
    if (presence == null ||
        (roomIds != null && roomIds!.contains(presence.roomId))) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: CallPresenceMark(
          conversationId: conversationId,
          color: Theme.of(context).colorScheme.onSurface,
          label: true,
        ),
      ),
    );
  }
}
