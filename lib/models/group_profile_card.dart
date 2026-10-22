import 'profile_card.dart' show ImageFocal;

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
    this.iconFocal,
    this.backgroundFocal,
  });

  final String name;
  final String description;
  final String? iconUrl;
  final String? iconStoragePath;
  final String? backgroundImageUrl;
  final String? backgroundImageStoragePath;

  /// アイコン・背景画像のどこを中心に、どれだけ拡大して見せるか（個人の工房
  /// カードの`ProfileCard.iconFocal`/`backgroundFocal`と同じ。2026-10-22）。
  /// 未指定は中央・等倍。画像を差し替えると構図もやり直す。
  final ImageFocal? iconFocal;
  final ImageFocal? backgroundFocal;

  GroupProfileCard copyWith({
    String? name,
    String? description,
    String? iconUrl,
    String? iconStoragePath,
    String? backgroundImageUrl,
    String? backgroundImageStoragePath,
    ImageFocal? iconFocal,
    bool clearIconFocal = false,
    ImageFocal? backgroundFocal,
    bool clearBackgroundFocal = false,
  }) {
    return GroupProfileCard(
      name: name ?? this.name,
      description: description ?? this.description,
      iconUrl: iconUrl ?? this.iconUrl,
      iconStoragePath: iconStoragePath ?? this.iconStoragePath,
      backgroundImageUrl: backgroundImageUrl ?? this.backgroundImageUrl,
      backgroundImageStoragePath:
          backgroundImageStoragePath ?? this.backgroundImageStoragePath,
      iconFocal: clearIconFocal ? null : iconFocal ?? this.iconFocal,
      backgroundFocal: clearBackgroundFocal
          ? null
          : backgroundFocal ?? this.backgroundFocal,
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
      iconFocal: ImageFocal.fromJson(json['iconFocal']),
      backgroundFocal: ImageFocal.fromJson(json['backgroundFocal']),
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
      if (iconFocal != null) 'iconFocal': iconFocal!.toJson(),
      if (backgroundFocal != null) 'backgroundFocal': backgroundFocal!.toJson(),
    };
  }
}
