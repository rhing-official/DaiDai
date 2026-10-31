/// 一対・広場どちらの通話も、STUNに加えてTURN（中継サーバー）を使えるようにする。
/// 別回線同士（モバイル回線など）は、STUNだけでは直接つながれず、音声も映像も
/// 届かないことがあるため（2026-10-21、実機で確認）。TURNの認証情報は、通話の開始時に
/// サーバー（Cloud Functions `getTurnCredentials`、Cloudflare Realtime TURN）から
/// 取得する。取得に失敗しても通話は止めず、STUNだけで続行する。
///
/// 従来の環境変数（`DAIDAI_TURN_URL`等、自前のcoturn用）も、設定されていれば
/// そのまま追加する（未設定なら何もしない）。
library;

const _turnUrl = String.fromEnvironment('DAIDAI_TURN_URL');
const _turnUsername = String.fromEnvironment('DAIDAI_TURN_USERNAME');
const _turnCredential = String.fromEnvironment('DAIDAI_TURN_CREDENTIAL');

/// TURNを含む`iceServers`の追加分を取得する関数（`TurnCredentialsRepository.fetchIceServers`）。
typedef IceServersLoader = Future<List<Map<String, dynamic>>> Function();

Map<String, dynamic> buildRtcConfiguration({
  List<Map<String, dynamic>> extraIceServers = const [],
}) => {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    if (_turnUrl.isNotEmpty)
      {
        'urls': _turnUrl,
        'username': _turnUsername,
        'credential': _turnCredential,
      },
    ...extraIceServers,
  ],
};

/// TURNの認証情報を取得して一定時間使い回す[IceServersLoader]（2026-10-31追加）。
/// 通話の開始ごとに取得すると、Cloud Functionsのコールドスタートで待ち時間を超え、
/// STUNだけで始まって別回線同士がつながらないことがあった。認証情報は4時間有効
/// （`getTurnCredentials`）なので、[ttl]の間は取得済みの結果を返す。取得中に
/// 別の呼び出しが来たら同じ取得を待つ。失敗した結果は覚えない。
class CachedIceServersLoader {
  CachedIceServersLoader(
    this._base, {
    this.ttl = const Duration(hours: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final IceServersLoader _base;
  final Duration ttl;
  final DateTime Function() _now;

  List<Map<String, dynamic>>? _cached;
  DateTime? _fetchedAt;
  Future<List<Map<String, dynamic>>>? _inFlight;

  Future<List<Map<String, dynamic>>> call() {
    final cached = _cached;
    final at = _fetchedAt;
    if (cached != null && at != null && _now().difference(at) < ttl) {
      return Future.value(cached);
    }
    return _inFlight ??= _base()
        .then((servers) {
          _cached = servers;
          _fetchedAt = _now();
          return servers;
        })
        .whenComplete(() => _inFlight = null);
  }

  /// 通話の前に取得を始めておく。失敗は無視する（通話の開始時に再び試す）。
  void prefetch() => call().ignore();
}

/// [loader]でTURNの認証情報を取得して設定を組み立てる。[loader]がnull、または
/// 取得に失敗・時間切れ（[timeout]）の場合は、STUNだけの設定を返す
/// （通話の開始を、中継サーバーの取得で長く待たせない）。
Future<Map<String, dynamic>> loadRtcConfiguration(
  IceServersLoader? loader, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (loader == null) return buildRtcConfiguration();
  try {
    final servers = await loader().timeout(timeout);
    return buildRtcConfiguration(extraIceServers: servers);
  } catch (_) {
    return buildRtcConfiguration();
  }
}
