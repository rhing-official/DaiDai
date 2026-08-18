import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/call/camera_availability.dart';

/// 端末のカメラ有無（[CameraAvailability]）。最初にwatchされた時点で
/// [probeCameraAvailability]を1回だけ実行し、以後はRiverpodが結果を
/// キャッシュする（ポーリング等の継続的な監視は行わない）。チャット
/// ヘッダーのビデオ通話発信アイコン・通話中の音声⇔ビデオ切替ボタンの
/// 表示可否に使う（2026-08-19追加）。
final cameraAvailabilityProvider = FutureProvider<CameraAvailability>((ref) {
  return probeCameraAvailability();
});
