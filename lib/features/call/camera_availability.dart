import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// 端末にカメラが搭載されているかの大まかな判定
/// （[lib/providers/camera_availability_provider.dart]参照）。
enum CameraAvailability {
  /// カメラが1台も無いと判定できた（主にネイティブプラットフォームでのみ
  /// 信頼できる。[probeCameraAvailability]のdocコメント参照）。
  unavailable,

  /// カメラが1台以上ある。
  present,

  /// 判定できなかった（Webでの権限許可前など）。誤ってビデオ通話の
  /// 選択肢を消さないよう、利用可能として扱う。
  unknown,
}

/// 端末のカメラ有無を1回だけ調べる（継続的な監視は行わない、呼び出し元の
/// `cameraAvailabilityProvider`がRiverpodで結果をキャッシュする）。
/// `flutter_webrtc`の`Helper.cameras`はブラウザの権限許可前だと台数を
/// 過少報告することがある（パッケージ本体のdocコメントにも明記あり）ため、
/// Web版で0台と判定された場合は「不明」として扱い、ビデオ通話の選択肢を
/// 誤って消さないようにする（カメラを実際に持っているのに隠してしまう方が、
/// 持っていないのに出したままにするより悪い体験になるため）。
Future<CameraAvailability> probeCameraAvailability() async {
  try {
    final cameras = await Helper.cameras;
    if (cameras.isEmpty) {
      return kIsWeb
          ? CameraAvailability.unknown
          : CameraAvailability.unavailable;
    }
    return CameraAvailability.present;
  } catch (_) {
    return CameraAvailability.unknown;
  }
}
