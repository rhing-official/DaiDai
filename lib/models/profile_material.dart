/// 身だしなみ（プロフィール）の蔵に保管できる素材の上限数。
const kMaxIcons = 2;
const kMaxBackgroundImages = 3;
const kMaxStatusMessages = 2;
const kMaxNicknames = 3;

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

/// 蔵に保管するニックネーム。Rhing IDとは別に、友達に対して表示される呼び名。
/// 最大[kMaxNicknames]件まで登録でき、その中から使うものを1つ選べる
/// （アイコン・背景画像・ステメと同じ「登録して選ぶ」方式）。
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
