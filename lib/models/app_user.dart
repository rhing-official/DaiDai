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
    this.snsLinks = const [],
    this.profileCards = const [],
    this.activeIconId,
    this.activeBackgroundImageId,
    this.activeStatusMessageId,
    this.activeNicknameId,
    this.activeProfileCardId,
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

  /// 蔵に保管している他のSNSのURL（最大[kMaxSnsLinks]件）。
  final List<SnsLink> snsLinks;

  /// 和合で作成したプロフィールカード（最大[kMaxProfileCards]枚）。
  /// 蔵の素材を組み合わせて作る「見せ方のセット」。
  final List<ProfileCard> profileCards;

  /// 現在表示に使っている素材のid。未選択ならnull。
  final String? activeIconId;
  final String? activeBackgroundImageId;
  final String? activeStatusMessageId;
  final String? activeNicknameId;

  /// 縁結びの招待リンク等に適用する、工房で作成したプロフィールカードのid。
  /// 未選択（null）の場合は、リンク側は個別の蔵アイテム（activeIcon/activeNickname）
  /// から直接組み立てる（[UserRepository.syncInvitePreview]参照）。
  final String? activeProfileCardId;

  ProfileMaterial? get activeIcon => _findMaterial(icons, activeIconId);
  ProfileMaterial? get activeBackgroundImage =>
      _findMaterial(backgroundImages, activeBackgroundImageId);
  StatusMessage? get activeStatusMessage =>
      _findStatusMessage(statusMessages, activeStatusMessageId);
  Nickname? get activeNickname => _findNickname(nicknames, activeNicknameId);
  ProfileCard? get activeProfileCard =>
      _findProfileCard(profileCards, activeProfileCardId);

  /// 表示に使うべきアイコン。適用中のプロフィールカード（[activeProfileCard]）
  /// があればそのカードが指すアイコンを優先し、未適用なら個別の蔵アイテムの
  /// [activeIcon]にフォールバックする。友達一覧・メンバー一覧など、相手の
  /// アイコンを表示するすべての箇所はこのgetterを使うこと。
  ProfileMaterial? get effectiveIcon {
    final card = activeProfileCard;
    return card != null ? _findMaterial(icons, card.iconId) : activeIcon;
  }

  /// [effectiveIcon]と同様、適用中のプロフィールカードのニックネームを優先する。
  Nickname? get effectiveNickname {
    final card = activeProfileCard;
    return card != null ? _findNickname(nicknames, card.nicknameId) : activeNickname;
  }

  /// [effectiveIcon]と同様、適用中のプロフィールカードのステメを優先する。
  StatusMessage? get effectiveStatusMessage {
    final card = activeProfileCard;
    return card != null
        ? _findStatusMessage(statusMessages, card.statusMessageId)
        : activeStatusMessage;
  }

  /// [effectiveIcon]と同様、適用中のプロフィールカードの背景画像を優先する。
  ProfileMaterial? get effectiveBackgroundImage {
    final card = activeProfileCard;
    return card != null
        ? _findMaterial(backgroundImages, card.backgroundImageId)
        : activeBackgroundImage;
  }

  /// 適用中のプロフィールカードに掲載しているSNSのURL一覧
  /// （カード未適用時は空リスト。個別のactiveXxxに相当する概念はSNS URLには無い）。
  List<SnsLink> get effectiveSnsLinks {
    final card = activeProfileCard;
    if (card == null) return const [];
    return [
      for (final link in snsLinks)
        if (card.snsLinkIds.contains(link.id)) link,
    ];
  }

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

  static ProfileCard? _findProfileCard(List<ProfileCard> items, String? id) {
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
    List<SnsLink>? snsLinks,
    List<ProfileCard>? profileCards,
    String? activeIconId,
    String? activeBackgroundImageId,
    String? activeStatusMessageId,
    String? activeNicknameId,
    String? activeProfileCardId,
    bool clearActiveProfileCardId = false,
  }) {
    return AppUser(
      userId: userId,
      rhingId: rhingId,
      displayName: displayName,
      icons: icons ?? this.icons,
      backgroundImages: backgroundImages ?? this.backgroundImages,
      statusMessages: statusMessages ?? this.statusMessages,
      nicknames: nicknames ?? this.nicknames,
      snsLinks: snsLinks ?? this.snsLinks,
      profileCards: profileCards ?? this.profileCards,
      activeIconId: activeIconId ?? this.activeIconId,
      activeBackgroundImageId:
          activeBackgroundImageId ?? this.activeBackgroundImageId,
      activeStatusMessageId:
          activeStatusMessageId ?? this.activeStatusMessageId,
      activeNicknameId: activeNicknameId ?? this.activeNicknameId,
      activeProfileCardId: clearActiveProfileCardId
          ? null
          : (activeProfileCardId ?? this.activeProfileCardId),
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
      snsLinks: _snsLinkListFromJson(json['snsLinks']),
      profileCards: _profileCardListFromJson(json['profileCards']),
      activeIconId: json['activeIconId'] as String?,
      activeBackgroundImageId: json['activeBackgroundImageId'] as String?,
      activeStatusMessageId: json['activeStatusMessageId'] as String?,
      activeNicknameId: json['activeNicknameId'] as String?,
      activeProfileCardId: json['activeProfileCardId'] as String?,
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
      'snsLinks': snsLinks.map((s) => s.toJson()).toList(),
      'profileCards': profileCards.map((c) => c.toJson()).toList(),
      'activeIconId': activeIconId,
      'activeBackgroundImageId': activeBackgroundImageId,
      'activeStatusMessageId': activeStatusMessageId,
      'activeNicknameId': activeNicknameId,
      'activeProfileCardId': activeProfileCardId,
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

  static List<SnsLink> _snsLinkListFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => SnsLink.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static List<ProfileCard> _profileCardListFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => ProfileCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
