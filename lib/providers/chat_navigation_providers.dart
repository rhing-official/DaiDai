import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/direct_message.dart';

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
