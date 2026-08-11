/// 一対・広場どちらの通話もSTUNに加えてTURN（自前coturn）を使う
/// （2026-07-24にまず広場通話で導入、その後の映像不通不具合の調査を経て
/// 一対通話にも同様に配線した）。coturnサーバー自体の構築（VM・DNS・証明書）は
/// 別途インフラ作業として必要で、ここではURL・認証情報を設定するだけの状態。
/// 実際のサーバーが立つまではSTUNのみで動作する
/// （未設定時は空文字のままiceServersから除外する）。
const _turnUrl = String.fromEnvironment('DAIDAI_TURN_URL');
const _turnUsername = String.fromEnvironment('DAIDAI_TURN_USERNAME');
const _turnCredential = String.fromEnvironment('DAIDAI_TURN_CREDENTIAL');

Map<String, dynamic> buildRtcConfiguration() => {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    if (_turnUrl.isNotEmpty)
      {
        'urls': _turnUrl,
        'username': _turnUsername,
        'credential': _turnCredential,
      },
  ],
};
