import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// モバイル（Android/iOS）実機かどうか。Web版は常にfalse
/// （`kIsWeb`が先に評価されるため`Platform`自体には触れない）。通話UIの
/// 全画面/PC埋め込み表示の出し分け（2026-08-19追加）等、画面幅ではなく
/// 実際のプラットフォームで判定したい場面に使う。
bool get isMobileCallPlatform =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// `local_auth`パッケージが生体認証（Face ID/Touch ID/指紋、Android
/// BiometricPrompt）を実質サポートするプラットフォームかどうか
/// （2026-09-11追加）。Web・Windows・Linuxは対象外（`local_auth`が
/// 未対応/実質使えないため）。パスコードロック機能自体は全プラットフォーム
/// で使えるが、生体認証トグルの表示可否はこれで判定する。
bool get isBiometricCapablePlatform =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

/// 着信音・呼出音のカスタム音源アップロード（`file_picker`でファイル選択→
/// Firebase Storageへアップロード）が使えるプラットフォームかどうか
/// （2026-09-12追加）。Windowsは`firebase_options.dart`が未設定でアプリ自体
/// まだ起動できず、LinuxはFirebase未設定に加え`firebase_storage`パッケージが
/// そもそもLinux向け実装を持たないため、恒久的にアップロード非対応となる
/// 見込み。プリセットからの選択自体は全プラットフォームで使える。
bool get isSoundUploadCapablePlatform =>
    kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
