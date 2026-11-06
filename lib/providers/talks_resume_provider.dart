import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/direct_message.dart';
import '../models/group.dart';

/// 語らいで開いている会話（一対か広場のどちらか1つ、2026-11-06）。メッセージ画面
/// （`DmChatPane`・`GroupChatPane`）が開いている間だけ自分を記録し、閉じたら消す。
class OpenChat {
  const OpenChat.dm(DirectMessage this.dm) : group = null;
  const OpenChat.group(Group this.group) : dm = null;

  final DirectMessage? dm;
  final Group? group;

  String get conversationId => dm?.dmId ?? group!.groupId;
}

class OpenChatNotifier extends Notifier<OpenChat?> {
  @override
  OpenChat? build() => null;

  void open(OpenChat chat) => state = chat;

  /// [conversationId]の会話を開いている場合だけ消す（別の会話が先に開かれていたら残す）。
  void close(String conversationId) {
    if (state?.conversationId == conversationId) state = null;
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
