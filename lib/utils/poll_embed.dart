import '../models/poll.dart';

/// メッセージ内に選択肢をそのまま出す（埋め込む）上限の選択肢数（2026-11-07）。
/// これを超える投票は小さいカードに折りたたみ、タップでダイアログを開く。
const int kPollEmbedMaxOptions = 4;

/// 投票を埋め込まず小さいカードに折りたたむか。画像・動画付きの選択肢が1つでもある、
/// または選択肢が[kPollEmbedMaxOptions]件を超える場合（`文書/投票埋め込み.md`）。
bool shouldCollapsePoll(Poll poll) {
  if (poll.options.length > kPollEmbedMaxOptions) return true;
  return poll.options.values.any((o) => o.hasImage || o.hasVideo);
}
