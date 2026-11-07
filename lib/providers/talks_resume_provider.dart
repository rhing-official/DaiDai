import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/direct_message.dart';
import '../models/group.dart';

/// 語らいで開いている会話（一対か広場のどちらか1つ、2026-11-06）。メッセージ画面
/// （`DmChatPane`・`GroupChatPane`）が開いている間だけ自分を記録し、閉じたら消す。
/// 開き直しに必要な寄合（[roomId]・[roomName]）と寄合タブバーの有無も持つ。
class OpenChat {
  const OpenChat.dm(
    DirectMessage this.dm, {
    required this.roomId,
    required this.roomName,
    this.showRoomTabBar = true,
  }) : group = null;
  const OpenChat.group(
    Group this.group, {
    required this.roomId,
    required this.roomName,
    this.showRoomTabBar = true,
  }) : dm = null;

  final DirectMessage? dm;
  final Group? group;
  final String roomId;
  final String roomName;
  final bool showRoomTabBar;

  String get conversationId => dm?.dmId ?? group!.groupId;
}

class OpenChatNotifier extends Notifier<OpenChat?> {
  /// 今の記録を書いたメッセージ画面（`State`）。寄合の切り替えでStateが作り直される時、
  /// 新しいStateの記録の後に古いStateの`close`が走るため、会話IDの一致だけで消すと
  /// 新しい記録まで消えてしまう（開き直しが取りこぼされた、2026-11-06）。
  Object? _owner;

  @override
  OpenChat? build() => null;

  /// [owner]（呼び出したStateなど）の記録として書く。同じ[owner]の再記録は寄合の更新になる。
  void open(OpenChat chat, {required Object owner}) {
    _owner = owner;
    state = chat;
  }

  /// 今の記録を書いたのが[owner]の時だけ消す（別のStateが新しく記録していたら残す）。
  void close(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    state = null;
  }
}

final openChatProvider = NotifierProvider<OpenChatNotifier, OpenChat?>(
  OpenChatNotifier.new,
);

/// 別のタブ（身だしなみの仕立てなど）へ移る時に閉じられた会話を、語らいに戻った時に
/// 開き直す為の記録（2026-11-06）。スマホではメッセージ画面が全画面のルートで、ほかの
/// タブを見せるには閉じる必要がある。戻ったら直ぐ作業を再開できるよう、ここに残す。
class TalksResumeNotifier extends Notifier<OpenChat?> {
  @override
  OpenChat? build() => null;

  void save(OpenChat chat) => state = chat;

  /// 残っていれば返して消す（1回限り）。
  OpenChat? consume() {
    final saved = state;
    state = null;
    return saved;
  }
}

final talksResumeProvider = NotifierProvider<TalksResumeNotifier, OpenChat?>(
  TalksResumeNotifier.new,
);
