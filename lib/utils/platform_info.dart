import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart' show BuildContext, MediaQuery;

/// モバイル（Android/iOS）実機かどうか。Web版は常にfalse
/// （`kIsWeb`が先に評価されるため`Platform`自体には触れない）。通話UIの
/// 全画面/PC埋め込み表示の出し分け（2026-08-19追加）等、画面幅ではなく
/// 実際のプラットフォームで判定したい場面に使う。
bool get isMobileCallPlatform =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// コンピューター・タブレット・スマホの3値の端末分類（2026-09-13追加、
/// 語らい検索の別ページ遷移の判定用）。ネイティブアプリ・Web版のどちらも
/// 同じロジックで判定する（同じ端末でネイティブアプリとブラウザで結果が
/// 食い違わないようにするため）。
///
/// OS情報だけ（`defaultTargetPlatform`）ではタブレット専用の値が無く
/// iPhone/iPadを区別できない上、iPadOS 13以降のSafariはUser-Agentを
/// macOSと同一にして送るためWeb版はそもそもOS単体で判別不能、
/// `device_info_plus`等のネイティブ限定プラグインを使えばiOSの機種
/// 識別子で判定は可能だがWeb版・Androidには使えず同一端末でネイティブ
/// アプリとブラウザの判定結果が食い違ってしまう。そのため画面サイズ＋
/// アスペクト比による判定に統一する（[classifyDevice]参照）。
enum DeviceClass { computer, tablet, phone }

/// [DeviceClass.tablet]と判定する論理サイズ短辺の閾値（dp）。
/// `talks_tab.dart`の`kIconSplitPeekBreakpoint`・`home_screen.dart`の
/// `_kWideLayoutBreakpoint`と同じ600を踏襲する。
const kTabletShortestSideThreshold = 600.0;

/// 短辺が[kTabletShortestSideThreshold]未満の場合に、スマホ（縦長）か
/// 小型タブレット（正方形に近い）かをさらに分けるアスペクト比
/// （縦横比の長い方÷短い方）の閾値。iPhoneは概ね2.0〜2.2、一般的な
/// タブレットは1.3〜1.6程度のため、1.6を境界とする。
const kPhoneAspectRatioThreshold = 1.6;

/// 実行中の端末を[DeviceClass]に分類する。まず`defaultTargetPlatform`
/// （Web上でもUser-Agent由来でOSを判定できる）でモバイル系OS
/// （Android/iOS）かどうかを判定し、モバイル系OS以外は常に
/// [DeviceClass.computer]。モバイル系OSの場合は論理サイズ
/// （`MediaQuery.sizeOf(context)`、devicePixelRatioで正規化済み）の
/// 短辺・アスペクト比でタブレット/スマホをさらに判定する。
/// [isMobileCallPlatform]は通話UI専用の別判定のため変更しない。
DeviceClass classifyDevice(BuildContext context) {
  final isMobileOs =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (!isMobileOs) return DeviceClass.computer;
  final size = MediaQuery.sizeOf(context);
  if (size.shortestSide >= kTabletShortestSideThreshold) {
    return DeviceClass.tablet;
  }
  final aspectRatio = size.longestSide / size.shortestSide;
  return aspectRatio >= kPhoneAspectRatioThreshold
      ? DeviceClass.phone
      : DeviceClass.tablet;
}

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
