import 'package:flutter/material.dart';

import '../features/chat/join_group_screen.dart';
import '../features/profile/invite_screen.dart';
import '../repositories/link_preview_repository.dart';
import 'app_dialog.dart';

/// DaiDai自身の招待リンク（`/invite/…`・`/join/…`）なら、画面を切り替えずに
/// ポップアップで開く（チャット内のリンク・リンクカードのタップ、2026-11-09）。
/// 招待リンクでなければ何もせず`false`を返す（呼び出し側が従来どおり外部で開く）。
Future<bool> openInviteLinkDialog(BuildContext context, String url) async {
  final invite = InviteAwareLinkPreviewRepository.parseInvite(url);
  if (invite == null) return false;
  await showAppDialog<void>(
    context: context,
    builder: (_) => invite.kind == 'invite'
        ? InviteScreen(rhingSeed: invite.id, asDialog: true)
        : JoinGroupScreen(groupId: invite.id, asDialog: true),
  );
  return true;
}
