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
    this.volume = 1.0,
  });

  final String soundId;
  final String name;
  final String storagePath;
  final String mimeType;
  final String createdBy;
  final DateTime? createdAt;

  /// この効果音だけの音量（0〜1、既定1。全体の音量に掛ける）。
  final double volume;
}

/// 名前での絞り込み（大文字小文字を区別しない。空なら全て）。
List<SoundboardSound> filterSoundboardSounds(
  List<SoundboardSound> sounds,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return sounds;
  return [
    for (final s in sounds)
      if (s.name.toLowerCase().contains(q)) s,
  ];
}

/// サウンド名の最大文字数（`firestore.rules`と同じ値にそろえること）。
const int kMaxSoundboardNameLength = 40;

/// 効果音1つの容量の上限。数秒の短い音を想定（`storage.rules`と同じ値にそろえること）。
const int kMaxSoundboardSoundBytes = 2 * 1024 * 1024;

/// 1つの会話（広場・一対）に登録できる効果音の数。
const int kMaxSoundboardSounds = 30;
