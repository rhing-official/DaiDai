import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../utils/platform_info.dart';

/// アプリ起動時のパスコードロック機能（2026-09-11追加、生体認証対応）向けの
/// 抽象化。設定は端末ローカルのみで完結し、Firestoreへは一切同期しない
/// （生体認証が本質的に端末固有の機能であるため、パスコードも合わせて
/// 端末ローカルにする方針。CLAUDE.md参照）。
abstract class PasscodeRepository {
  /// パスコードが設定済みかどうか。
  Future<bool> isPasscodeSet();

  /// 6桁の数字文字列を新しいパスコードとして保存する。
  Future<void> setPasscode(String code);

  /// [code]が現在設定されているパスコードと一致するか確認する。
  Future<bool> verifyPasscode(String code);

  /// パスコード自体と生体認証設定を両方削除する（無効化・サインアウト時の
  /// リセットで使う）。
  Future<void> clearPasscode();

  /// 生体認証での解除が有効化されているか。
  Future<bool> isBiometricEnabled();

  Future<void> setBiometricEnabled(bool enabled);

  /// この端末・プラットフォームで生体認証が使えるか（対応プラットフォームで、
  /// かつOSに1つ以上の生体情報が登録済みか）。
  Future<bool> canUseBiometrics();

  /// OSの生体認証プロンプトを表示し、認証結果を返す。
  Future<bool> authenticateWithBiometrics();
}

class SecureStoragePasscodeRepository implements PasscodeRepository {
  SecureStoragePasscodeRepository({
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuth,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _localAuth = localAuth ?? LocalAuthentication();

  static const _passcodeKey = 'passcodeLock.code';
  static const _biometricEnabledKey = 'passcodeLock.biometricEnabled';

  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _localAuth;

  @override
  Future<bool> isPasscodeSet() async {
    return await _secureStorage.read(key: _passcodeKey) != null;
  }

  @override
  Future<void> setPasscode(String code) {
    return _secureStorage.write(key: _passcodeKey, value: code);
  }

  @override
  Future<bool> verifyPasscode(String code) async {
    final stored = await _secureStorage.read(key: _passcodeKey);
    return stored != null && stored == code;
  }

  @override
  Future<void> clearPasscode() async {
    await _secureStorage.delete(key: _passcodeKey);
    await _secureStorage.delete(key: _biometricEnabledKey);
  }

  @override
  Future<bool> isBiometricEnabled() async {
    return await _secureStorage.read(key: _biometricEnabledKey) == 'true';
  }

  @override
  Future<void> setBiometricEnabled(bool enabled) {
    return _secureStorage.write(
      key: _biometricEnabledKey,
      value: enabled.toString(),
    );
  }

  @override
  Future<bool> canUseBiometrics() async {
    if (!isBiometricCapablePlatform) return false;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } on Exception {
      return false;
    }
  }

  @override
  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'パスコードロックを解除',
        biometricOnly: true,
      );
    } on Exception {
      return false;
    }
  }
}
