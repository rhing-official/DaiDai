/// 1端末につき登録できるプッシュ通知トークンの上限数。
const kMaxFcmTokens = 10;

/// プッシュ通知（FCM）送信先の1端末分。`AppUser.fcmTokens`に保管する。
/// `platform`でCloud Functions側の送信方法（Androidはdata-only、Webは
/// `webpush`ペイロード）を出し分ける。
class FcmTokenEntry {
  const FcmTokenEntry({required this.token, required this.platform});

  final String token;

  /// 'web' | 'android'。
  final String platform;

  factory FcmTokenEntry.fromJson(Map<String, dynamic> json) {
    return FcmTokenEntry(
      token: json['token'] as String,
      platform: json['platform'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'token': token, 'platform': platform};
  }
}
