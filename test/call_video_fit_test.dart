import 'package:daidai/features/call/call_tile_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  test('メインは縦長の領域でCover、横長でContain、コーナーは常にCover', () {
    expect(
      callVideoFitFor(portraitArea: true, main: true),
      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
    expect(
      callVideoFitFor(portraitArea: false, main: true),
      RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
    );
    expect(
      callVideoFitFor(portraitArea: false, main: false),
      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
    expect(
      callVideoFitFor(portraitArea: true, main: false),
      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  });
}
