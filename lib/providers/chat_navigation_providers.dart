import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/direct_message.dart';
import '../models/group.dart';

/// プロフィールカードダイアログ等、`TalksTab`の外側（別のWidgetツリー）から
/// 「この一対を開いてほしい」と伝えるための一時的な橋渡し。`TalksTab`が
/// この値の変化を`ref.listen`で受け取り、自身の`_openDirectMessage`（一覧の
/// 一対をクリックした時と全く同じ処理）に渡してから、この値をnullに戻す。
///
/// 単純に`goRouterProvider`で`/chat/dm`にpushすると、左右分割表示
/// （`TalksTab`が自前のStateで一覧＋チャットを同時表示している構成）の時に
/// サイドバーごと覆う全画面ルートが積まれてしまい、一覧から開いた場合と
/// 見え方が変わってしまうバグがあった（2026-07-29修正）。
class PendingDmSelectionNotifier extends Notifier<DirectMessage?> {
  @override
  DirectMessage? build() => null;

  void set(DirectMessage dm) => state = dm;

  void clear() => state = null;
}

final pendingDmSelectionProvider =
    NotifierProvider<PendingDmSelectionNotifier, DirectMessage?>(
      PendingDmSelectionNotifier.new,
    );

/// [PendingDmSelectionNotifier]の広場版（2026-08-19追加、通話ミニ表示
/// タップでの復帰用）。`TalksTab`が同じ`ref.listen`パターンで受け取り、
/// `_openGroup`に渡す。
class PendingGroupSelectionNotifier extends Notifier<Group?> {
  @override
  Group? build() => null;

  void set(Group group) => state = group;

  void clear() => state = null;
}

final pendingGroupSelectionProvider =
    NotifierProvider<PendingGroupSelectionNotifier, Group?>(
      PendingGroupSelectionNotifier.new,
    );

/// 現在画面に表示中の会話（一対/広場）。通話のPC埋め込み表示・ピン留め
/// ミニ表示（`lib/features/call/`配下）が「今その会話を見ているか」を
/// 判定するために使う（2026-08-19追加）。`DmChatPane`/`GroupChatPane`
/// （`EmbeddedCallPane`経由）が自身のマウント中にセットし、アンマウント時に
/// クリアする。`TalksTab`の左右分割表示・`/chat/dm`・`/chat/group`の
/// フルスクリーン遷移のどちらも同じ`DmChatPane`/`GroupChatPane`を経由する
/// ため、ここ1箇所で両方カバーできる。
sealed class ViewedConversation {
  const ViewedConversation();
}

class ViewedDm extends ViewedConversation {
  const ViewedDm(this.dmId);
  final String dmId;

  @override
  bool operator ==(Object other) => other is ViewedDm && other.dmId == dmId;

  @override
  int get hashCode => Object.hash(ViewedDm, dmId);
}

class ViewedGroup extends ViewedConversation {
  const ViewedGroup(this.groupId);
  final String groupId;

  @override
  bool operator ==(Object other) =>
      other is ViewedGroup && other.groupId == groupId;

  @override
  int get hashCode => Object.hash(ViewedGroup, groupId);
}

class ActiveConversationNotifier extends Notifier<ViewedConversation?> {
  @override
  ViewedConversation? build() => null;

  void set(ViewedConversation conversation) => state = conversation;

  /// 表示中がまさに[conversation]の場合だけクリアする（アンマウント時に
  /// 呼ばれるが、その間に別の会話へ切り替わっていた場合は上書きしない）。
  void clearIfCurrent(ViewedConversation conversation) {
    if (state == conversation) state = null;
  }
}

final activeConversationProvider =
    NotifierProvider<ActiveConversationNotifier, ViewedConversation?>(
      ActiveConversationNotifier.new,
    );
