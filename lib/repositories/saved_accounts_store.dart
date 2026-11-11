import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/saved_account.dart';

/// この端末に保存した切り替え用のアカウントの入れ物（2026-11-11、複数アカウント）。
/// 合言葉を含むので、`flutter_secure_storage`にだけ保存する（Webでは暗号化して
/// ブラウザに保存。鍵も同じブラウザ内にあるため、XSSには強くない）。
abstract class SavedAccountsStore {
  Future<List<SavedAccount>> load();

  /// [account]を保存する（同じ`uid`があれば置き換える）。
  Future<void> save(SavedAccount account);

  Future<void> remove(String uid);

  Future<PendingAccountAdd?> loadPending();
  Future<void> savePending(PendingAccountAdd pending);
  Future<void> clearPending();
}

class SecureSavedAccountsStore implements SavedAccountsStore {
  SecureSavedAccountsStore({FlutterSecureStorage? secureStorage})
    : _storage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accountsKey = 'savedAccounts.v1';
  static const _pendingKey = 'savedAccounts.pendingAdd.v1';

  @override
  Future<List<SavedAccount>> load() async {
    final raw = await _storage.read(key: _accountsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(SavedAccount.tryFromJson)
          .whereType<SavedAccount>()
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> _write(List<SavedAccount> accounts) {
    if (accounts.isEmpty) return _storage.delete(key: _accountsKey);
    return _storage.write(
      key: _accountsKey,
      value: jsonEncode([for (final a in accounts) a.toJson()]),
    );
  }

  @override
  Future<void> save(SavedAccount account) async {
    final current = await load();
    await _write([
      for (final a in current)
        if (a.uid != account.uid) a,
      account,
    ]);
  }

  @override
  Future<void> remove(String uid) async {
    final current = await load();
    await _write([
      for (final a in current)
        if (a.uid != uid) a,
    ]);
  }

  @override
  Future<PendingAccountAdd?> loadPending() async {
    final raw = await _storage.read(key: _pendingKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PendingAccountAdd.tryFromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> savePending(PendingAccountAdd pending) =>
      _storage.write(key: _pendingKey, value: jsonEncode(pending.toJson()));

  @override
  Future<void> clearPending() => _storage.delete(key: _pendingKey);
}
