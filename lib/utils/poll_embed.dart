import '../models/poll.dart';

/// メッセージ内に選択肢をそのまま出す（埋め込む）上限の選択肢数（2026-11-07）。
/// これを超える投票は小さいカードに折りたたみ、タップでダイアログを開く。
const int kPollEmbedMaxOptions = 4;

/// 投票を埋め込まず小さいカードに折りたたむか。選択肢が[kPollEmbedMaxOptions]件を
/// 超える場合だけ（`文書/投票埋め込み.md`）。画像・動画付きの選択肢も、選択肢の左の
/// サムネイルとして埋め込みのまま出して、メッセージ画面から答えられる（2026-11-08、
/// 以前は1つでもあれば折りたたみ、ダイアログからしか答えられなかった）。
bool shouldCollapsePoll(Poll poll) {
  return poll.options.length > kPollEmbedMaxOptions;
}
