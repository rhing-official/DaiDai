import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/chat/talks_search.dart' show MessageSearchHit;
import '../models/direct_message.dart';
import '../models/group.dart';
import '../providers/chat_navigation_providers.dart';
import '../providers/home_shell_providers.dart';
import '../providers/last_opened_room_provider.dart';
import '../router/app_router.dart';

/// 一対・広場を、ユーザーが設定した語らいレイアウト（`TalksListLayoutStyle`、
/// 設定>アプリケーション）どおりの見え方で開く（2026-10-11追加）。
///
/// 招待URL・広場作成直後・通知タップ等から`/chat/group`・`/chat/dm`へ直接
/// pushすると、設定に関わらず常にフルスクリーンのチャット画面（画面最上に
/// 寄合のタブバー）が開いてしまい、語らいタブで一覧から開いた時と見え方が
/// 変わっていた。ここでは語らいタブ（`TalksTab`）へ戻して「この会話を開いて」と
/// 伝え、`TalksTab._openGroup`/`_openDirectMessage`（一覧をタップした時と全く
/// 同じ処理）に分割表示・アイコン＋寄合一覧・フルスクリーンの振り分けを任せる。
///
/// [roomId]を渡すと、その寄合を開く（`lastOpenedRoomProvider`へ先に記録し、
/// どのレイアウトでも「最後に開いた寄合」として拾われる）。省略時は、最後に
/// 開いた寄合（無ければ先頭）。
Future<void> openGroupInTalks(
  WidgetRef ref,
  Group group, {
  String? roomId,
}) async {
  if (roomId != null) {
    await ref
        .read(lastOpenedRoomProvider.notifier)
        .setLastRoom(ViewedGroup(group.groupId), roomId);
  }
  _goToTalksTab(ref);
  ref.read(pendingGroupSelectionProvider.notifier).set(group);
}

/// [openGroupInTalks]の一対版。
Future<void> openDmInTalks(
  WidgetRef ref,
  DirectMessage dm, {
  String? roomId,
}) async {
  if (roomId != null) {
    await ref
        .read(lastOpenedRoomProvider.notifier)
        .setLastRoom(ViewedDm(dm.dmId), roomId);
  }
  _goToTalksTab(ref);
  ref.read(pendingDmSelectionProvider.notifier).set(dm);
}

/// 語らい検索のメッセージ内容一致を、語らいタブで設定どおりの見え方で開く
/// （該当メッセージへのジャンプ込み、`TalksTab._openMessageSearchHit`が処理）。
void openMessageHitInTalks(WidgetRef ref, MessageSearchHit hit) {
  _goToTalksTab(ref);
  ref.read(pendingMessageSearchHitProvider.notifier).set(hit);
}

/// ホームの語らいタブへ戻す（積まれているフルスクリーンのルートは全て閉じる）。
void _goToTalksTab(WidgetRef ref) {
  ref.read(goRouterProvider).go('/');
  ref.read(homeSelectedTabProvider.notifier).set(kTalksTabIndex);
}
