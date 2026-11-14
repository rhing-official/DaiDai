import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 端末ローカルの設定のうち、アカウントを切り替えても退避・削除しないものの接頭辞・キー。
/// パスコードロックは端末単位（アカウントに紐づかない）。退避データ自体と持ち主の記録、
/// 端末の通知チャンネルに紐づく準備済みの印も対象外。
const _keepPrefixes = ['passcodeLock.', _snapshotPrefix];
const _keepKeys = {_ownerKey, 'notificationSoundCustomChannelReadyUrl'};

const _ownerKey = 'localStateOwnerUid';
const _snapshotPrefix = 'accountSnapshot.';

bool _isAccountBound(String key) =>
    !_keepPrefixes.any(key.startsWith) && !_keepKeys.contains(key);

/// アカウントごとに端末の設定を保つ（2026-11-14）。キーにuidが付いていないため、
/// 今の`SharedPreferences`が「誰の設定か」を[_ownerKey]に持ち、アカウントが変わる時に
/// 前の持ち主の設定を`accountSnapshot.<uid>`へ退避して、新しい持ち主の退避を復元する。
/// 退避は消さない（ログアウトしてもアンインストールまで残る）。退避が無いアカウントは
/// 初期状態で始まる。
///
/// 持ち主が[uid]と同じなら何もしない。持ち主が未登録（この機能の初回）なら、今の設定を
/// [uid]のものとして登録するだけで消さない。再読み込みが要る時（設定が入れ替わった時）に
/// `true`を返す。
Future<bool> swapLocalStateTo(String uid) async {
  final prefs = await SharedPreferences.getInstance();
  final owner = prefs.getString(_ownerKey);
  if (owner == uid) return false;
  if (owner == null) {
    await prefs.setString(_ownerKey, uid);
    return false;
  }
  await _saveSnapshot(prefs, owner);
  for (final key in prefs.getKeys().toList()) {
    if (_isAccountBound(key)) await prefs.remove(key);
  }
  await _restoreSnapshot(prefs, uid);
  await prefs.setString(_ownerKey, uid);
  return true;
}

Future<void> _saveSnapshot(SharedPreferences prefs, String uid) async {
  final map = <String, Object>{};
  for (final key in prefs.getKeys()) {
    if (!_isAccountBound(key)) continue;
    final value = prefs.get(key);
    if (value is String) {
      map[key] = {'t': 's', 'v': value};
    } else if (value is int) {
      map[key] = {'t': 'i', 'v': value};
    } else if (value is double) {
      map[key] = {'t': 'd', 'v': value};
    } else if (value is bool) {
      map[key] = {'t': 'b', 'v': value};
    } else if (value is List<String>) {
      map[key] = {'t': 'l', 'v': value};
    }
  }
  await prefs.setString('$_snapshotPrefix$uid', jsonEncode(map));
}

Future<void> _restoreSnapshot(SharedPreferences prefs, String uid) async {
  final raw = prefs.getString('$_snapshotPrefix$uid');
  if (raw == null) return;
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    for (final entry in map.entries) {
      final item = entry.value as Map<String, dynamic>;
      final v = item['v'];
      switch (item['t']) {
        case 's':
          await prefs.setString(entry.key, v as String);
        case 'i':
          await prefs.setInt(entry.key, (v as num).toInt());
        case 'd':
          await prefs.setDouble(entry.key, (v as num).toDouble());
        case 'b':
          await prefs.setBool(entry.key, v as bool);
        case 'l':
          await prefs.setStringList(
            entry.key,
            (v as List<dynamic>).cast<String>(),
          );
      }
    }
  } catch (_) {
    // 壊れた退避は無視する（そのアカウントは初期状態で始まる）。
  }
}
