import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/app_user.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../providers/repository_providers.dart';
import '../../utils/open_conversation.dart';

/// プッシュ通知タップ時、`dmId`/`groupId`（＋任意の`roomId`）だけから
/// 該当の語らいを開くための解決役（2026-09-02追加）。
///
/// `app_router.dart`の既存の`/chat/dm`・`/chat/group`ルートは、TalksTab側で
/// 既に取得済みの`AppUser`・`DirectMessage`/`Group`オブジェクト一式を
/// `state.extra`で受け取る設計のため、通知タップ（cold start含む）のように
/// ID単体しか持たない場面では使えない。ここでは対象の一対/広場を取得し、
/// 寄合が有効か確認してから、語らいタブへ「この会話を開いて」と伝える
/// （[openDmInTalks]/[openGroupInTalks]）。以前はここで`DmChatPane`/
/// `GroupChatPane`を直接フルスクリーン表示していたが、設定した語らい
/// レイアウト（アイコン＋寄合一覧・左右分割）が無視されるため、語らいタブ
/// 経由に変更した（2026-10-11）。取得できない会話（削除済み・自分が参加者で
/// ない）はホームへ戻す。
class NotificationChatOpener extends ConsumerStatefulWidget {
  const NotificationChatOpener({
    required this.currentUser,
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    super.key,
  });

  final AppUser currentUser;
  final bool isDm;
  final String conversationId;

  /// 通知ペイロード由来のroomId（無効・未指定なら語らいタブ側の既定
  /// ＝最後に開いた寄合（無ければ先頭）にフォールバック）。
  final String? roomId;

  @override
  ConsumerState<NotificationChatOpener> createState() =>
      _NotificationChatOpenerState();
}

class _NotificationChatOpenerState
    extends ConsumerState<NotificationChatOpener> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    if (widget.isDm) {
      final resolved = await _resolveDm();
      if (!mounted) return;
      if (resolved == null) {
        context.go('/');
        return;
      }
      await openDmInTalks(ref, resolved.dm, roomId: resolved.roomId);
    } else {
      final resolved = await _resolveGroup();
      if (!mounted) return;
      if (resolved == null) {
        context.go('/');
        return;
      }
      await openGroupInTalks(ref, resolved.group, roomId: resolved.roomId);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 解決が終わるまでの一瞬だけ表示される空の画面。
    return const Scaffold(body: SizedBox.shrink());
  }

  /// 通知で指定された寄合が実在する時だけその寄合を返す（無ければnull＝
  /// 語らいタブ側の既定に任せる）。
  String? _validRoomId(Iterable<String> roomIds) =>
      roomIds.firstWhereOrNull((id) => id == widget.roomId);

  Future<({DirectMessage dm, String? roomId})?> _resolveDm() async {
    final repository = ref.read(directMessageRepositoryProvider);
    final dm = await repository.getDirectMessage(widget.conversationId);
    if (dm == null || !dm.participants.contains(widget.currentUser.userId)) {
      return null;
    }
    final rooms = await repository
        .watchRooms(dmId: dm.dmId, userId: widget.currentUser.userId)
        .first;
    // 健全な一対は常に1件以上の寄合を持つ（`talks_tab.dart`の
    // `_openDirectMessage`と同じ理由）。
    if (rooms.isEmpty) return null;
    return (dm: dm, roomId: _validRoomId(rooms.map((r) => r.roomId)));
  }

  Future<({Group group, String? roomId})?> _resolveGroup() async {
    final repository = ref.read(groupRepositoryProvider);
    final group = await repository.getGroup(widget.conversationId);
    if (group == null || !group.memberIds.contains(widget.currentUser.userId)) {
      return null;
    }
    final rooms = await repository
        .watchRooms(groupId: group.groupId, userId: widget.currentUser.userId)
        .first;
    // [_resolveDm]と同じ理由。
    if (rooms.isEmpty) return null;
    return (group: group, roomId: _validRoomId(rooms.map((r) => r.roomId)));
  }
}
