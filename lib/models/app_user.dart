import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user_preferences.dart';
import 'fcm_token_entry.dart';
import 'profile_card.dart';
import 'profile_material.dart';

/// アカウント削除の状態。active: 通常。pendingDeletion: 削除申請済みで
/// 30日間の復元猶予期間中（[AppUser.deletionRequestedAt]参照）。suspended:
/// 運営（管理画面）による手動停止中（2026-08-12追加。技術仕様書8.4の
/// スパム対策による期限付き自動停止とは別の、シンプルな手動停止/解除のみ）。
enum AccountStatus {
  active,
  pendingDeletion,
  suspended;

  static AccountStatus fromName(String name) => AccountStatus.values.firstWhere(
    (s) => s.name == name,
    orElse: () => AccountStatus.active,
  );
}

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
    this.fcmTokens = const [],
    this.activeIconId,
    this.activeBackgroundImageId,
    this.activeStatusMessageId,
    this.activeNicknameId,
    this.activeProfileCardId,
    this.conversationProfileCardId = const {},
    this.preferences = AppUserPreferences.empty,
    this.accountStatus = AccountStatus.active,
    this.deletionRequestedAt,
    this.createdAt,
    this.lastLoginAt,
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

  /// プッシュ通知（FCM）の送信先端末一覧（最大[kMaxFcmTokens]件、
  /// `PushNotificationRepository`が登録・削除する）。
  final List<FcmTokenEntry> fcmTokens;

  /// 現在表示に使っている素材のid。未選択ならnull。
  final String? activeIconId;
  final String? activeBackgroundImageId;
  final String? activeStatusMessageId;
  final String? activeNicknameId;

  /// 縁結びの招待リンク等に適用する、工房で作成したプロフィールカードのid。
  /// 未選択（null）の場合は、リンク側は個別の蔵アイテム（activeIcon/activeNickname）
  /// から直接組み立てる（[UserRepository.syncInvitePreview]参照）。
  final String? activeProfileCardId;

  /// 会話（一対のdmId・広場のgroupId）ごとに使うプロフィールカードのid
  /// （2026-07-29追加）。エントリが無い会話は[activeProfileCardId]（標準）が
  /// 適用される。[profileCardFor]/[effectiveIconFor]等の会話対応版ゲッター
  /// から参照する。
  final Map<String, String> conversationProfileCardId;

  /// 端末をまたいで同期する表示設定（設定タブのアクセントカラー・外観・
  /// 表示言語等）。[UserRepository.updateUserPreference]で個別に部分更新する。
  final AppUserPreferences preferences;

  /// アカウント削除の状態。[AccountStatus.pendingDeletion]の場合、
  /// [deletionRequestedAt]から31日後にCloud Functionsの定期処理が
  /// サーバーから全情報を完全削除する（`UserRepository.requestAccountDeletion`/
  /// `restoreAccount`参照）。
  final AccountStatus accountStatus;

  /// アカウント削除を申請した日時。[accountStatus]が
  /// [AccountStatus.pendingDeletion]の場合のみ意味を持つ。
  final Timestamp? deletionRequestedAt;

  /// アカウント作成日時（2026-08-12追加、管理画面向け）。`toJson()`自体には
  /// 含めず、`UserRepository.createUser`が新規作成時のみ`FieldValue.
  /// serverTimestamp()`を個別にマージして書き込む（`updateUser`は同じ
  /// `toJson()`を`.set()`で全体上書きしているため、`toJson()`にサーバー
  /// タイムスタンプを混ぜるとプロフィール更新のたびに現在時刻へリセット
  /// されてしまう事故を避けるため）。既存ユーザーはnullのままで、
  /// 管理画面では「不明」表示になる。
  final Timestamp? createdAt;

  /// 最終ログイン日時（2026-08-12追加、管理画面向け）。`UserRepository.
  /// touchLastLogin`が認証済みセッション確認のたびに更新する、独立した
  /// フィールド（理由は[createdAt]と同様、`updateUser`経由での事故を
  /// 避けるため）。
  final Timestamp? lastLoginAt;

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
    return card != null
        ? _findNickname(nicknames, card.nicknameId)
        : activeNickname;
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

  /// [conversationId]（一対のdmId・広場のgroupId）に指定された会話専用の
  /// プロフィールカードがあればそれを返し、無ければ[activeProfileCard]
  /// （標準）にフォールバックする。会話ごとのカード切り替え機能
  /// （2026-07-29追加）の基点となるゲッター。
  ProfileCard? profileCardFor(String? conversationId) {
    if (conversationId != null) {
      final overrideId = conversationProfileCardId[conversationId];
      final card = _findProfileCard(profileCards, overrideId);
      if (card != null) return card;
    }
    return activeProfileCard;
  }

  /// [effectiveIcon]の会話対応版。[profileCardFor]で解決したカードが
  /// あればそのアイコンを、無ければ[activeIcon]を返す。
  ProfileMaterial? effectiveIconFor(String? conversationId) {
    final card = profileCardFor(conversationId);
    return card != null ? _findMaterial(icons, card.iconId) : activeIcon;
  }

  /// [effectiveNickname]の会話対応版。
  Nickname? effectiveNicknameFor(String? conversationId) {
    final card = profileCardFor(conversationId);
    return card != null
        ? _findNickname(nicknames, card.nicknameId)
        : activeNickname;
  }

  /// [effectiveStatusMessage]の会話対応版。
  StatusMessage? effectiveStatusMessageFor(String? conversationId) {
    final card = profileCardFor(conversationId);
    return card != null
        ? _findStatusMessage(statusMessages, card.statusMessageId)
        : activeStatusMessage;
  }

  /// [effectiveBackgroundImage]の会話対応版。
  ProfileMaterial? effectiveBackgroundImageFor(String? conversationId) {
    final card = profileCardFor(conversationId);
    return card != null
        ? _findMaterial(backgroundImages, card.backgroundImageId)
        : activeBackgroundImage;
  }

  /// [effectiveSnsLinks]の会話対応版。
  List<SnsLink> effectiveSnsLinksFor(String? conversationId) {
    final card = profileCardFor(conversationId);
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
    Map<String, String>? conversationProfileCardId,
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
      conversationProfileCardId:
          conversationProfileCardId ?? this.conversationProfileCardId,
      preferences: preferences,
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
      fcmTokens: _fcmTokenListFromJson(json['fcmTokens']),
      activeIconId: json['activeIconId'] as String?,
      activeBackgroundImageId: json['activeBackgroundImageId'] as String?,
      activeStatusMessageId: json['activeStatusMessageId'] as String?,
      activeNicknameId: json['activeNicknameId'] as String?,
      activeProfileCardId: json['activeProfileCardId'] as String?,
      conversationProfileCardId:
          (json['conversationProfileCardId'] as Map?)?.cast<String, String>() ??
          const {},
      preferences: AppUserPreferences.fromJson(
        json['preferences'] as Map<String, dynamic>?,
      ),
      accountStatus: AccountStatus.fromName(
        json['accountStatus'] as String? ?? AccountStatus.active.name,
      ),
      deletionRequestedAt: json['deletionRequestedAt'] as Timestamp?,
      createdAt: json['createdAt'] as Timestamp?,
      lastLoginAt: json['lastLoginAt'] as Timestamp?,
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
      'fcmTokens': fcmTokens.map((t) => t.toJson()).toList(),
      'activeIconId': activeIconId,
      'activeBackgroundImageId': activeBackgroundImageId,
      'activeStatusMessageId': activeStatusMessageId,
      'activeNicknameId': activeNicknameId,
      'activeProfileCardId': activeProfileCardId,
      'conversationProfileCardId': conversationProfileCardId,
      'preferences': preferences.toJson(),
      'accountStatus': accountStatus.name,
      'deletionRequestedAt': deletionRequestedAt,
      'createdAt': createdAt,
      'lastLoginAt': lastLoginAt,
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

  static List<FcmTokenEntry> _fcmTokenListFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => FcmTokenEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
