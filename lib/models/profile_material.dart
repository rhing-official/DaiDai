import 'font_design.dart';

/// 身だしなみ（プロフィール）の蔵に保管できる素材の上限数。
const kMaxIcons = 5;
const kMaxBackgroundImages = 3;
const kMaxStatusMessages = 10;
const kMaxNicknames = 10;
const kMaxSnsLinks = 5;
const kMaxFontDesigns = 5;

/// 工房のプロフィールカード1枚に掲載できるSNSのURLの上限数。
const kMaxProfileCardSnsLinks = 2;

/// 蔵の素材の文字数上限。
const kMaxNicknameLength = 20;
const kMaxStatusMessageLength = 40;

/// 蔵に保管する画像素材（アイコン・背景画像）。
class ProfileMaterial {
  const ProfileMaterial({
    required this.id,
    required this.url,
    required this.storagePath,
  });

  final String id;
  final String url;
  final String storagePath;

  factory ProfileMaterial.fromJson(Map<String, dynamic> json) {
    return ProfileMaterial(
      id: json['id'] as String,
      url: json['url'] as String,
      storagePath: json['storagePath'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'url': url, 'storagePath': storagePath};
  }
}

/// 蔵に保管するステメ（ステータスメッセージ）。
class StatusMessage {
  const StatusMessage({required this.id, required this.text});

  final String id;
  final String text;

  factory StatusMessage.fromJson(Map<String, dynamic> json) {
    return StatusMessage(
      id: json['id'] as String,
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'text': text};
  }
}

/// 蔵に保管するニックネーム。Rhing Seedとは別に、友達に対して表示される呼び名。
/// 最大[kMaxNicknames]件まで登録できる。友達に表示される1件は選択式ではなく
/// 登録順で自動的に決まる。
class Nickname {
  const Nickname({required this.id, required this.text});

  final String id;
  final String text;

  factory Nickname.fromJson(Map<String, dynamic> json) {
    return Nickname(id: json['id'] as String, text: json['text'] as String);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'text': text};
  }
}

/// 蔵に保管するフォントデザイン（2026-09-26追加）。工房のプロフィールカードに
/// 割り当てると、そのカードの呼び名・一言・URLは[design]のフォントで固定表示
/// され、見る側の端末のフォントデザイン設定（設定＞アプリケーション）に
/// 関わらず変わらなくなる。[design]が`null`の場合は「システムと同じ」
/// （＝今まで通り見る側の設定を継承し、上書きしない）を表す。
/// 最大[kMaxFontDesigns]件まで登録できる。
class FontDesignMaterial {
  const FontDesignMaterial({required this.id, this.design});

  final String id;

  /// nullなら「システムと同じ」。
  final FontDesign? design;

  factory FontDesignMaterial.fromJson(Map<String, dynamic> json) {
    return FontDesignMaterial(
      id: json['id'] as String,
      design: json['design'] != null
          ? FontDesign.fromName(json['design'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'design': design?.name};
  }
}

/// 蔵に保管する他のSNSのURL。最大[kMaxSnsLinks]件まで登録でき、そのうち
/// 工房のプロフィールカード1枚に掲載できるのは最大[kMaxProfileCardSnsLinks]件。
class SnsLink {
  const SnsLink({required this.id, required this.url});

  final String id;
  final String url;

  factory SnsLink.fromJson(Map<String, dynamic> json) {
    return SnsLink(id: json['id'] as String, url: json['url'] as String);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'url': url};
  }
}
