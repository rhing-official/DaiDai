import '../services/app_functions.dart';

import '../models/saved_account.dart';

/// 切り替えに失敗した理由（2026-11-11）。サーバーの文言は日本語のみなので、画面には
/// [kind]から選んだ表示言語の文言を出す。
enum SwitchAccountFailure {
  /// 極みの契約が切れている（所有者も本人も極みでない）。追加の時は、極みではない。
  kiwamiRequired,

  /// 合言葉が無効・期限切れ・失効など。もう一度ログインが要る。
  reloginNeeded,

  /// 保存できる数の上限。
  limitReached,

  other,
}

class SwitchAccountException implements Exception {
  const SwitchAccountException(this.kind, [this.message]);

  final SwitchAccountFailure kind;
  final String? message;

  @override
  String toString() => 'SwitchAccountException($kind, $message)';
}

/// 複数アカウントの切り替え用の合言葉を、サーバー（Cloud Functions）で作る・検証する・
/// 失効させる入り口（2026-11-11）。UIからFirebase SDKを直接叩かない。
abstract class SwitchSessionRepository {
  /// 別のアカウントを追加するためのチケット（10分・1回限り）を作る。極みのアカウントだけ。
  Future<({String ticket, int expiresAtMs})> createTicket();

  /// 今ログインしているアカウントの合言葉を作る。極みでなければ[ticket]が要る。
  Future<SavedAccount> createSession({String? ticket, String rhingSeed = ''});

  /// 保存した合言葉で切り替え、カスタムトークンを返す（未ログインでも呼べる）。
  Future<String> redeem(SavedAccount account);

  /// 保存したアカウントを取り外す。
  Future<void> revoke(SavedAccount account);
}

class FirebaseSwitchSessionRepository implements SwitchSessionRepository {
  FirebaseSwitchSessionRepository({AppFunctions? functions})
    : _functions =
          functions ?? AppFunctions.instanceFor(region: 'asia-northeast1');

  final AppFunctions _functions;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, Object?> data,
  ) async {
    try {
      final result = await _functions.httpsCallable(name).call(data);
      return Map<String, dynamic>.from(result.data as Map);
    } on AppFunctionsException catch (error) {
      throw SwitchAccountException(_failureFor(error.code), error.message);
    }
  }

  static SwitchAccountFailure _failureFor(String code) => switch (code) {
    'failed-precondition' => SwitchAccountFailure.kiwamiRequired,
    'permission-denied' ||
    'deadline-exceeded' ||
    'not-found' ||
    'unauthenticated' => SwitchAccountFailure.reloginNeeded,
    'resource-exhausted' => SwitchAccountFailure.limitReached,
    _ => SwitchAccountFailure.other,
  };

  @override
  Future<({String ticket, int expiresAtMs})> createTicket() async {
    final data = await _call('createSwitchTicket', const {});
    return (
      ticket: data['ticket'] as String,
      expiresAtMs: (data['expiresAtMs'] as num).toInt(),
    );
  }

  @override
  Future<SavedAccount> createSession({
    String? ticket,
    String rhingSeed = '',
  }) async {
    final data = await _call('createSwitchSession', {'ticket': ?ticket});
    return SavedAccount(
      uid: data['uid'] as String,
      sessionId: data['sessionId'] as String,
      secret: data['secret'] as String,
      rhingSeed: rhingSeed,
    );
  }

  @override
  Future<String> redeem(SavedAccount account) async {
    final data = await _call('redeemSwitchSession', {
      'uid': account.uid,
      'sessionId': account.sessionId,
      'secret': account.secret,
    });
    return data['customToken'] as String;
  }

  @override
  Future<void> revoke(SavedAccount account) async {
    await _call('revokeSwitchSession', {
      'uid': account.uid,
      'sessionId': account.sessionId,
      'secret': account.secret,
    });
  }
}
