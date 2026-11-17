import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers/conversation_call_providers.dart';

/// 語らい一覧の箱・寄合一覧・寄合タブに出す「通話中」の標（2026-11-17）。通話中の電話/
/// ビデオのアイコンと、入っている人数（取得できている間だけ）。通話が無ければ何も出さない。
/// [conversationId]は一対のdmId・広場のgroupId。[label]を付けると文言も出す（寄合一覧用）。
class CallPresenceMark extends ConsumerWidget {
  const CallPresenceMark({
    required this.conversationId,
    required this.color,
    this.label = false,
    this.size = 16,
    super.key,
  });

  final String conversationId;
  final Color color;
  final bool label;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presence = ref.watch(conversationCallProvider(conversationId));
    if (presence == null) return const SizedBox.shrink();
    final strings = ref.watch(appStringsProvider);
    final count = presence.users.length;
    return Tooltip(
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
  }
}

/// 寄合タブの下に出す、通話中の細い帯（2026-11-17）。通話は広場（一対）単位で、特定の寄合には
/// 属さないため、タブのどれにも付けず、バーとは別に1行で出す。通話が無ければ高さ0。
class CallPresenceBar extends ConsumerWidget {
  const CallPresenceBar({required this.conversationId, super.key});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(conversationCallProvider(conversationId)) == null) {
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
