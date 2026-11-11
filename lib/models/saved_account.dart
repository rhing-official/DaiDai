import 'profile_card.dart';

/// この端末に保存した、切り替え用のアカウント（2026-11-11、複数アカウント）。
/// [secret]は切り替え用の合言葉で、サーバーにはそのハッシュだけがある。
/// 端末の`flutter_secure_storage`にだけ保存し、外へ出さない。
class SavedAccount {
  const SavedAccount({
    required this.uid,
    required this.sessionId,
    required this.secret,
    required this.rhingSeed,
    this.iconUrl,
    this.iconFocal,
  });

  final String uid;
  final String sessionId;
  final String secret;

  /// 一覧に出す表示用（保存した時点のRhing Seed）。
  final String rhingSeed;

  /// 一覧に出す、そのアカウントの標準のアイコン（`AppUser.effectiveIcon`）の写し。
  /// 未ログインのアカウントはFirestoreを読めないため、そのアカウントを使っている間に
  /// 端末へ写す（2026-11-11）。nullなら生成アバターを出す。
  final String? iconUrl;
  final ImageFocal? iconFocal;

  SavedAccount withIcon(String? url, ImageFocal? focal) => SavedAccount(
    uid: uid,
    sessionId: sessionId,
    secret: secret,
    rhingSeed: rhingSeed,
    iconUrl: url,
    iconFocal: focal,
  );

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'sessionId': sessionId,
    'secret': secret,
    'rhingSeed': rhingSeed,
    if (iconUrl != null) 'iconUrl': iconUrl,
    if (iconFocal != null) 'iconFocal': iconFocal!.toJson(),
  };

  static SavedAccount? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final uid = json['uid'];
    final sessionId = json['sessionId'];
    final secret = json['secret'];
    final rhingSeed = json['rhingSeed'];
    if (uid is! String || sessionId is! String || secret is! String) {
      return null;
    }
    return SavedAccount(
      uid: uid,
      sessionId: sessionId,
      secret: secret,
      rhingSeed: rhingSeed is String ? rhingSeed : '',
      iconUrl: json['iconUrl'] is String ? json['iconUrl'] as String : null,
      iconFocal: ImageFocal.fromJson(json['iconFocal']),
    );
  }
}

/// アカウントを追加している途中の状態。極みのアカウントが発行した追加チケットを持って
/// サインアウトし、別のアカウントでログインした直後に使う（[ticket]は10分・1回限り）。
class PendingAccountAdd {
  const PendingAccountAdd({
    required this.ticket,
    required this.expiresAtMs,
    required this.fromUid,
  });

  final String ticket;
  final int expiresAtMs;

  /// 追加元（極みのアカウント）のuid。
  final String fromUid;

  Map<String, dynamic> toJson() => {
    'ticket': ticket,
    'expiresAtMs': expiresAtMs,
    'fromUid': fromUid,
  };

  static PendingAccountAdd? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final ticket = json['ticket'];
    final expiresAtMs = json['expiresAtMs'];
    final fromUid = json['fromUid'];
    if (ticket is! String || expiresAtMs is! int || fromUid is! String) {
      return null;
    }
    return PendingAccountAdd(
      ticket: ticket,
      expiresAtMs: expiresAtMs,
      fromUid: fromUid,
    );
  }
}
