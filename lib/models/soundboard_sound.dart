/// 通話のサウンドボードに登録された効果音（2026-11-16）。追加した人のアカウントに保存し
/// （2026-11-17）、本人はどの語らいでも、追加した語らいのメンバーはその語らいで使える。
/// ファイルの場所は[storagePath]（ダウンロードURLではなく保存先のパス。自前化の方針）。
class SoundboardSound {
  const SoundboardSound({
    required this.soundId,
    required this.name,
    required this.storagePath,
    required this.mimeType,
    required this.createdBy,
    this.createdAt,
    this.volume = 1.0,
    this.originId,
    this.originIsDm = false,
  });

  final String soundId;
  final String name;
  final String storagePath;
  final String mimeType;
  final String createdBy;
  final DateTime? createdAt;

  /// この効果音だけの音量（0〜1、既定1。全体の音量に掛ける）。
  final double volume;

  /// 追加した語らい（一対か広場のid）。個人保存の音だけが持つ。以前の（語らい単位の）音は
  /// 持たない。
  final String? originId;
  final bool originIsDm;

  /// 追加した人のアカウントに保存された音か（個人保存。上限の対象）。
  bool get isPersonal => storagePath.startsWith(kPersonalSoundPathPrefix);
}

/// 個人保存の音のStorageパスの先頭（`soundboard/user/{uid}/{soundId}/audio.{拡張子}`）。
const String kPersonalSoundPathPrefix = 'soundboard/user/';

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

/// 1人が追加できる効果音の数（2026-11-17）。無料は5個、極みは10個。
const int kSoundboardLimitFree = 5;
const int kSoundboardLimitKiwami = 10;

int soundboardLimitFor({required bool kiwami}) =>
    kiwami ? kSoundboardLimitKiwami : kSoundboardLimitFree;

/// 語らいで出す効果音の一覧を作る（2026-11-17）。自分が追加した音（[mine]、個人保存）は
/// どの語らいでも出し、語らいに登録されている音（[inConversation]）のうち、[mine]に
/// 無いものを足す（他の人が追加した音と、以前の語らい単位の音）。
/// [memberIds]があれば（広場）、追加した人が今のメンバーでない音は出さない。
class SoundboardLists {
  const SoundboardLists({required this.mine, required this.shared});

  /// 「マイサウンド」。
  final List<SoundboardSound> mine;

  /// 「この語らい」。
  final List<SoundboardSound> shared;

  List<SoundboardSound> get all => [...mine, ...shared];
}

SoundboardLists composeSoundboardSounds({
  required String userId,
  required List<SoundboardSound> mine,
  required List<SoundboardSound> inConversation,
  Set<String>? memberIds,
}) {
  final mineIds = {for (final s in mine) s.soundId};
  return SoundboardLists(
    mine: mine,
    shared: [
      for (final s in inConversation)
        if (!mineIds.contains(s.soundId) &&
            (s.createdBy == userId ||
                memberIds == null ||
                memberIds.contains(s.createdBy)))
          s,
    ],
  );
}
