/// 広場のプロフィールカード名の最大文字数。
const kMaxGroupProfileCardNameLength = 30;

/// 広場のプロフィールカード説明文の最大文字数。
const kMaxGroupProfileCardDescriptionLength = 100;

/// 広場を代表するプロフィールカード。個人の工房カードと異なり蔵の素材を
/// 参照せず、アイコンURL・背景画像URL・名前・説明を直接持つ自己完結型の
/// モデル（広場にはユーザーのような蔵システムが無いため）。広場につき1枚のみ。
/// 個人の工房カード（[ProfileCard]・`_WorkshopCardSlot`）と同じ見た目
/// （背景画像＋グラデーション＋アイコン＋名前＋説明）で表示する（2026-07-25変更）。
class GroupProfileCard {
  const GroupProfileCard({
    required this.name,
    this.description = '',
    this.iconUrl,
    this.iconStoragePath,
    this.backgroundImageUrl,
    this.backgroundImageStoragePath,
  });

  final String name;
  final String description;
  final String? iconUrl;
  final String? iconStoragePath;
  final String? backgroundImageUrl;
  final String? backgroundImageStoragePath;

  GroupProfileCard copyWith({
    String? name,
    String? description,
    String? iconUrl,
    String? iconStoragePath,
    String? backgroundImageUrl,
    String? backgroundImageStoragePath,
  }) {
    return GroupProfileCard(
      name: name ?? this.name,
      description: description ?? this.description,
      iconUrl: iconUrl ?? this.iconUrl,
      iconStoragePath: iconStoragePath ?? this.iconStoragePath,
      backgroundImageUrl: backgroundImageUrl ?? this.backgroundImageUrl,
      backgroundImageStoragePath:
          backgroundImageStoragePath ?? this.backgroundImageStoragePath,
    );
  }

  factory GroupProfileCard.fromJson(Map<String, dynamic> json) {
    return GroupProfileCard(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      iconUrl: json['iconUrl'] as String?,
      iconStoragePath: json['iconStoragePath'] as String?,
      backgroundImageUrl: json['backgroundImageUrl'] as String?,
      backgroundImageStoragePath: json['backgroundImageStoragePath'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'iconUrl': iconUrl,
      'iconStoragePath': iconStoragePath,
      'backgroundImageUrl': backgroundImageUrl,
      'backgroundImageStoragePath': backgroundImageStoragePath,
    };
  }
}
