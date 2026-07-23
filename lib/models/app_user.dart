import 'profile_card.dart';
import 'profile_material.dart';

class AppUser {
  const AppUser({
    required this.userId,
    required this.rhingId,
    this.displayName,
    this.icons = const [],
    this.backgroundImages = const [],
    this.statusMessages = const [],
    this.nicknames = const [],
    this.profileCards = const [],
    this.activeIconId,
    this.activeBackgroundImageId,
    this.activeStatusMessageId,
    this.activeNicknameId,
  });

  final String userId;
  final String rhingId;
  final String? displayName;

  /// 蔵に保管しているアイコン素材（最大[kMaxIcons]件）。
  final List<ProfileMaterial> icons;

  /// 蔵に保管している背景画像素材（最大[kMaxBackgroundImages]件）。
  final List<ProfileMaterial> backgroundImages;

  /// 蔵に保管しているステメ（最大[kMaxStatusMessages]件）。
  final List<StatusMessage> statusMessages;

  /// 蔵に保管しているニックネーム（最大[kMaxNicknames]件）。
  /// 友達には、相手のRhing IDの代わりにここで選んだニックネームが表示される。
  final List<Nickname> nicknames;

  /// 和合で作成したプロフィールカード（最大[kMaxProfileCards]枚）。
  /// 蔵の素材を組み合わせて作る「見せ方のセット」。
  final List<ProfileCard> profileCards;

  /// 現在表示に使っている素材のid。未選択ならnull。
  final String? activeIconId;
  final String? activeBackgroundImageId;
  final String? activeStatusMessageId;
  final String? activeNicknameId;

  ProfileMaterial? get activeIcon => _findMaterial(icons, activeIconId);
  ProfileMaterial? get activeBackgroundImage =>
      _findMaterial(backgroundImages, activeBackgroundImageId);
  StatusMessage? get activeStatusMessage =>
      _findStatusMessage(statusMessages, activeStatusMessageId);
  Nickname? get activeNickname => _findNickname(nicknames, activeNicknameId);

  static ProfileMaterial? _findMaterial(
    List<ProfileMaterial> items,
    String? id,
  ) {
    if (id == null) return null;
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  static StatusMessage? _findStatusMessage(
    List<StatusMessage> items,
    String? id,
  ) {
    if (id == null) return null;
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  static Nickname? _findNickname(List<Nickname> items, String? id) {
    if (id == null) return null;
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  AppUser copyWith({
    List<ProfileMaterial>? icons,
    List<ProfileMaterial>? backgroundImages,
    List<StatusMessage>? statusMessages,
    List<Nickname>? nicknames,
    List<ProfileCard>? profileCards,
    String? activeIconId,
    String? activeBackgroundImageId,
    String? activeStatusMessageId,
    String? activeNicknameId,
  }) {
    return AppUser(
      userId: userId,
      rhingId: rhingId,
      displayName: displayName,
      icons: icons ?? this.icons,
      backgroundImages: backgroundImages ?? this.backgroundImages,
      statusMessages: statusMessages ?? this.statusMessages,
      nicknames: nicknames ?? this.nicknames,
      profileCards: profileCards ?? this.profileCards,
      activeIconId: activeIconId ?? this.activeIconId,
      activeBackgroundImageId:
          activeBackgroundImageId ?? this.activeBackgroundImageId,
      activeStatusMessageId:
          activeStatusMessageId ?? this.activeStatusMessageId,
      activeNicknameId: activeNicknameId ?? this.activeNicknameId,
    );
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      userId: json['userId'] as String,
      rhingId: json['rhingId'] as String,
      displayName: json['displayName'] as String?,
      icons: _materialListFromJson(json['icons']),
      backgroundImages: _materialListFromJson(json['backgroundImages']),
      statusMessages: _statusListFromJson(json['statusMessages']),
      nicknames: _nicknameListFromJson(json['nicknames']),
      profileCards: _profileCardListFromJson(json['profileCards']),
      activeIconId: json['activeIconId'] as String?,
      activeBackgroundImageId: json['activeBackgroundImageId'] as String?,
      activeStatusMessageId: json['activeStatusMessageId'] as String?,
      activeNicknameId: json['activeNicknameId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'rhingId': rhingId,
      'displayName': displayName,
      'icons': icons.map((m) => m.toJson()).toList(),
      'backgroundImages': backgroundImages.map((m) => m.toJson()).toList(),
      'statusMessages': statusMessages.map((m) => m.toJson()).toList(),
      'nicknames': nicknames.map((n) => n.toJson()).toList(),
      'profileCards': profileCards.map((c) => c.toJson()).toList(),
      'activeIconId': activeIconId,
      'activeBackgroundImageId': activeBackgroundImageId,
      'activeStatusMessageId': activeStatusMessageId,
      'activeNicknameId': activeNicknameId,
    };
  }

  static List<ProfileMaterial> _materialListFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => ProfileMaterial.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static List<StatusMessage> _statusListFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => StatusMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static List<Nickname> _nicknameListFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => Nickname.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static List<ProfileCard> _profileCardListFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => ProfileCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
