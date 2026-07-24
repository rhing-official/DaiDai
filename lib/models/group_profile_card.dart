/// 広場のプロフィールカード名の最大文字数。
const kMaxGroupProfileCardNameLength = 30;

/// 広場のプロフィールカード説明文の最大文字数。
const kMaxGroupProfileCardDescriptionLength = 100;

/// 広場を代表するプロフィールカード。個人の工房カードと異なり蔵の素材を
/// 参照せず、アイコンURL・名前・説明を直接持つ自己完結型のモデル
/// （広場にはユーザーのような蔵システムが無いため）。広場につき1枚のみ。
class GroupProfileCard {
  const GroupProfileCard({
    required this.name,
    this.description = '',
    this.iconUrl,
    this.iconStoragePath,
  });

  final String name;
  final String description;
  final String? iconUrl;
  final String? iconStoragePath;

  GroupProfileCard copyWith({
    String? name,
    String? description,
    String? iconUrl,
    String? iconStoragePath,
  }) {
    return GroupProfileCard(
      name: name ?? this.name,
      description: description ?? this.description,
      iconUrl: iconUrl ?? this.iconUrl,
      iconStoragePath: iconStoragePath ?? this.iconStoragePath,
    );
  }

  factory GroupProfileCard.fromJson(Map<String, dynamic> json) {
    return GroupProfileCard(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      iconUrl: json['iconUrl'] as String?,
      iconStoragePath: json['iconStoragePath'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'iconUrl': iconUrl,
      'iconStoragePath': iconStoragePath,
    };
  }
}
