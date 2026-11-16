/// 通話のサウンドボードに登録された効果音（2026-11-16）。広場・一対ごとにサーバーへ
/// 保存し、その会話の全員が使える。ファイルの場所は[storagePath]（ダウンロードURLでは
/// なく保存先のパス。自前化の方針）。
class SoundboardSound {
  const SoundboardSound({
    required this.soundId,
    required this.name,
    required this.storagePath,
    required this.mimeType,
    required this.createdBy,
    this.createdAt,
  });

  final String soundId;
  final String name;
  final String storagePath;
  final String mimeType;
  final String createdBy;
  final DateTime? createdAt;
}

/// 効果音1つの容量の上限。数秒の短い音を想定（`storage.rules`と同じ値にそろえること）。
const int kMaxSoundboardSoundBytes = 2 * 1024 * 1024;

/// 1つの会話（広場・一対）に登録できる効果音の数。
const int kMaxSoundboardSounds = 30;
