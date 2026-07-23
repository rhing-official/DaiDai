/// 和合で作成できるプロフィールカードの上限数。
const kMaxProfileCards = 3;

/// 和合（プロフィールカード）。蔵に登録済みの素材（アイコン・背景画像・
/// ニックネーム・ステメ）を組み合わせて作る「見せ方のセット」。
/// 用途は多岐（友達へのURL共有時の表示、友達バーのホバーポップアップなど）を
/// 想定しており、1人で最大[kMaxProfileCards]枚まで作成できる。
/// 各フィールドは蔵の素材のidを指す。未選択（null）も許容する。
class ProfileCard {
  const ProfileCard({
    required this.id,
    required this.name,
    this.iconId,
    this.backgroundImageId,
    this.nicknameId,
    this.statusMessageId,
  });

  final String id;

  /// カード自体の名前（例:「仕事用」「プライベート」）。本人だけが見る管理用ラベル。
  final String name;

  final String? iconId;
  final String? backgroundImageId;
  final String? nicknameId;
  final String? statusMessageId;

  ProfileCard copyWith({
    String? name,
    String? iconId,
    bool clearIconId = false,
    String? backgroundImageId,
    bool clearBackgroundImageId = false,
    String? nicknameId,
    bool clearNicknameId = false,
    String? statusMessageId,
    bool clearStatusMessageId = false,
  }) {
    return ProfileCard(
      id: id,
      name: name ?? this.name,
      iconId: clearIconId ? null : (iconId ?? this.iconId),
      backgroundImageId:
          clearBackgroundImageId ? null : (backgroundImageId ?? this.backgroundImageId),
      nicknameId: clearNicknameId ? null : (nicknameId ?? this.nicknameId),
      statusMessageId:
          clearStatusMessageId ? null : (statusMessageId ?? this.statusMessageId),
    );
  }

  factory ProfileCard.fromJson(Map<String, dynamic> json) {
    return ProfileCard(
      id: json['id'] as String,
      name: json['name'] as String,
      iconId: json['iconId'] as String?,
      backgroundImageId: json['backgroundImageId'] as String?,
      nicknameId: json['nicknameId'] as String?,
      statusMessageId: json['statusMessageId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'iconId': iconId,
      'backgroundImageId': backgroundImageId,
      'nicknameId': nicknameId,
      'statusMessageId': statusMessageId,
    };
  }
}
