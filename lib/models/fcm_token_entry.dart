/// 1端末につき登録出来るプッシュ通知トークンの上限数。
const kMaxFcmTokens = 10;

/// プッシュ通知（FCM）送信先の1端末分。`users/{uid}/private/fcm`に保管する。
/// `platform`でCloud Functions側の送信方法（Androidはdata-only、Webは
/// `webpush`ペイロード）を出し分ける。
class FcmTokenEntry {
  const FcmTokenEntry({
    required this.token,
    required this.platform,
    this.muted = false,
  });

  final String token;

  /// 'web' | 'android'。
  final String platform;

  /// この端末では、このアカウント宛ての通知を止めているか（2026-11-27）。Cloud Functionsが
  /// `true`のトークンへは送らない。無い（古い登録）はオン。
  final bool muted;

  factory FcmTokenEntry.fromJson(Map<String, dynamic> json) {
    return FcmTokenEntry(
      token: json['token'] as String,
      platform: json['platform'] as String,
      muted: json['muted'] == true,
    );
  }

  /// 止めていない時は`muted`を書かない（古い登録と同じ形のまま）。
  Map<String, dynamic> toJson() {
    return {'token': token, 'platform': platform, if (muted) 'muted': true};
  }
}
