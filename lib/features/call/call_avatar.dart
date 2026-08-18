import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/user_providers.dart';

/// 通話UI（全画面・PC埋め込み・ピン留めミニ表示）で使う、参加者の中央
/// アバター。[chat_screen.dart]の`_SenderAvatar`と同じく、[userId]の
/// `AppUser.effectiveIconFor(conversationId)`（蔵/工房で設定した会話ごとの
/// アイコン）があればそれを表示し、無ければRhing IDの頭文字イニシャルに
/// フォールバックする。通話UIは従来`rhingId`文字列のみを持ち回っており
/// アイコン解決を一切行っていなかった（2026-08-18修正）。
class CallParticipantAvatar extends ConsumerWidget {
  const CallParticipantAvatar({
    required this.userId,
    required this.rhingId,
    required this.conversationId,
    required this.radius,
    this.fontSize,
    super.key,
  });

  final String userId;
  final String rhingId;

  /// 一対のdmId、または広場のgroupId。
  final String? conversationId;

  final double radius;
  final double? fontSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(watchedUserProvider(userId)).value;
    final iconUrl = user?.effectiveIconFor(conversationId)?.url;
    if (iconUrl != null) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(iconUrl));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Text(
        rhingId.isNotEmpty ? rhingId[0].toUpperCase() : '?',
        style: TextStyle(fontSize: fontSize ?? radius * 0.7, color: Colors.white),
      ),
    );
  }
}
