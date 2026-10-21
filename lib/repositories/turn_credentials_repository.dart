import 'package:cloud_functions/cloud_functions.dart';

/// 通話の中継（TURN）サーバーの認証情報を取得する（2026-10-21追加）。
/// 別回線同士など、直接つながれない通話の中継に使う。認証情報は短時間だけ有効で、
/// キー自体はサーバー（Cloud Functions `getTurnCredentials`）の中にだけある。
abstract class TurnCredentialsRepository {
  /// `RTCPeerConnection`の`iceServers`にそのまま足せる形（`urls`・`username`・
  /// `credential`）で返す。取得できなかった時は例外を投げる（呼び出し側は
  /// STUNのみで続行する）。
  Future<List<Map<String, dynamic>>> fetchIceServers();
}

class FirebaseTurnCredentialsRepository implements TurnCredentialsRepository {
  FirebaseTurnCredentialsRepository({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFunctions _functions;

  @override
  Future<List<Map<String, dynamic>>> fetchIceServers() async {
    final result = await _functions.httpsCallable('getTurnCredentials').call();
    final servers = (result.data as Map)['iceServers'] as List;
    return [
      for (final server in servers)
        {
          'urls': List<String>.from((server as Map)['urls'] as List),
          if (server['username'] != null) 'username': server['username'],
          if (server['credential'] != null) 'credential': server['credential'],
        },
    ];
  }
}
