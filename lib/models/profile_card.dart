/// 和合で作成できるプロフィールカードの上限数。
const kMaxProfileCards = 3;

/// プロフィールカード名の文字数上限。
const kMaxWorkshopCardNameLength = 20;

/// 画像のどこを中心に見せるか（2026-10-11追加）。[dx]/[dy]は`Alignment`と同じ
/// -1〜1（0,0が中央＝従来の中央固定と同じ）、[scale]は1.0（ぴったり収める）
/// 〜[kMaxImageFocalScale]の拡大率。カード単位で持つ（同じ素材を複数のカードが
/// 使えるため、構図は素材ではなくカードの属性）。
class ImageFocal {
  const ImageFocal({this.dx = 0, this.dy = 0, this.scale = 1});

  static const center = ImageFocal();

  final double dx;
  final double dy;
  final double scale;

  bool get isDefault => dx == 0 && dy == 0 && scale == 1;

  ImageFocal copyWith({double? dx, double? dy, double? scale}) => ImageFocal(
    dx: (dx ?? this.dx).clamp(-1.0, 1.0),
    dy: (dy ?? this.dy).clamp(-1.0, 1.0),
    scale: (scale ?? this.scale).clamp(1.0, kMaxImageFocalScale),
  );

  /// 欠損・不正な値は中央・等倍にフォールバックする（古いデータとの互換）。
  static ImageFocal? fromJson(Object? json) {
    if (json is! Map) return null;
    double read(String key, double fallback) {
      final v = json[key];
      return v is num && v.isFinite ? v.toDouble() : fallback;
    }

    return ImageFocal.center.copyWith(
      dx: read('dx', 0),
      dy: read('dy', 0),
      scale: read('scale', 1),
    );
  }

  Map<String, dynamic> toJson() => {'dx': dx, 'dy': dy, 'scale': scale};

  @override
  bool operator ==(Object other) =>
      other is ImageFocal &&
      other.dx == dx &&
      other.dy == dy &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(dx, dy, scale);
}

/// 画像の拡大率の上限。
const kMaxImageFocalScale = 3.0;

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
    this.snsLinkIds = const [],
    this.fontDesignId,
    this.backgroundFocal,
    this.iconFocal,
  });

  final String id;

  /// カード自体の名前（例:「仕事用」「プライベート」）。本人だけが見る管理用ラベル。
  final String name;

  final String? iconId;
  final String? backgroundImageId;
  final String? nicknameId;
  final String? statusMessageId;

  /// このカードに固定表示するフォントデザイン（蔵の[FontDesignMaterial]の
  /// id）。未選択（null）なら見る側の端末設定を継承する（2026-09-26追加）。
  final String? fontDesignId;

  /// このカードに掲載するSNSのURL（蔵の[SnsLink]のid）。最大[kMaxProfileCardSnsLinks]件。
  final List<String> snsLinkIds;

  /// 背景画像・アイコンの中心指定（2026-10-11追加）。nullなら従来どおり中央。
  final ImageFocal? backgroundFocal;
  final ImageFocal? iconFocal;

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
    List<String>? snsLinkIds,
    String? fontDesignId,
    bool clearFontDesignId = false,
    ImageFocal? backgroundFocal,
    bool clearBackgroundFocal = false,
    ImageFocal? iconFocal,
    bool clearIconFocal = false,
  }) {
    return ProfileCard(
      id: id,
      name: name ?? this.name,
      iconId: clearIconId ? null : (iconId ?? this.iconId),
      backgroundImageId: clearBackgroundImageId
          ? null
          : (backgroundImageId ?? this.backgroundImageId),
      nicknameId: clearNicknameId ? null : (nicknameId ?? this.nicknameId),
      statusMessageId: clearStatusMessageId
          ? null
          : (statusMessageId ?? this.statusMessageId),
      snsLinkIds: snsLinkIds ?? this.snsLinkIds,
      fontDesignId: clearFontDesignId
          ? null
          : (fontDesignId ?? this.fontDesignId),
      backgroundFocal: clearBackgroundFocal
          ? null
          : (backgroundFocal ?? this.backgroundFocal),
      iconFocal: clearIconFocal ? null : (iconFocal ?? this.iconFocal),
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
      snsLinkIds: (json['snsLinkIds'] as List?)?.cast<String>() ?? const [],
      fontDesignId: json['fontDesignId'] as String?,
      backgroundFocal: ImageFocal.fromJson(json['backgroundFocal']),
      iconFocal: ImageFocal.fromJson(json['iconFocal']),
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
      'snsLinkIds': snsLinkIds,
      'fontDesignId': fontDesignId,
      if (backgroundFocal != null) 'backgroundFocal': backgroundFocal!.toJson(),
      if (iconFocal != null) 'iconFocal': iconFocal!.toJson(),
    };
  }
}

/// [cards]を[orderedIds]の順に並べ直す（2026-10-11追加、工房のドラッグ並べ替え）。
/// [orderedIds]に無いカード（別の端末で追加された分など）は消さずに末尾へ元の
/// 順で残し、存在しないidは無視する。
List<ProfileCard> reorderProfileCardsById(
  List<ProfileCard> cards,
  List<String> orderedIds,
) {
  final byId = {for (final c in cards) c.id: c};
  final result = <ProfileCard>[];
  for (final id in orderedIds) {
    final card = byId.remove(id);
    if (card != null) result.add(card);
  }
  result.addAll(byId.values);
  return result;
}
