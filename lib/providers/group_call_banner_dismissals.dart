import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 広場の語らいの上に出す「通話中」バナー（`GroupCallJoinBanner`）を、×で閉じた
/// 通話のid（2026-10-21追加）。通話id単位で覚える（新しい通話は新しいidなので、
/// また出る）。アプリを再起動すると忘れる。アプリ全体の最前面バナー
/// （`groupCallBannersProvider`）とは別で、そちらを閉じても、語らいを開けば出る。
class GroupCallBannerDismissalsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void dismiss(String groupCallId) => state = {...state, groupCallId};
}

final groupCallBannerDismissalsProvider =
    NotifierProvider<GroupCallBannerDismissalsNotifier, Set<String>>(
      GroupCallBannerDismissalsNotifier.new,
    );

/// バナーを出すかどうか（純粋な判定、テスト用）。進行中の通話があり、自分が
/// まだその通話に参加しておらず、閉じておらず、参加者が1人以上いる時だけ出す。
bool shouldShowGroupCallBanner({
  required String? activeGroupCallId,
  required String? joinedGroupCallId,
  required Set<String> dismissedIds,
  required int? liveParticipantCount,
}) {
  if (activeGroupCallId == null) return false;
  // 参加者が読み込み済みで、1人以上が入っている通話にだけ出す（2026-11-18）。読み込み中
  // （null、通話を掛けた直後で自分の参加もまだ）や、誰も入っていない通話（キャンセル・全員
  // 退出の直後）には、参加を促さない。
  if (liveParticipantCount == null || liveParticipantCount == 0) return false;
  if (joinedGroupCallId == activeGroupCallId) return false;
  return !dismissedIds.contains(activeGroupCallId);
}
