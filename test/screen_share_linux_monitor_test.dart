import 'package:daidai/features/call/screen_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const devices = [
    (id: 'a', label: 'Built-in Audio Analog Stereo', kind: 'audioinput'),
    (
      id: 'b',
      label: 'Monitor of Built-in Audio Analog Stereo',
      kind: 'audioinput',
    ),
    (id: 'c', label: 'Monitor of HDMI Output', kind: 'audioinput'),
    (id: 'd', label: 'Monitor of Speakers', kind: 'audiooutput'),
  ];

  test('Monitor入力だけを残す（出力デバイスやマイクは除く）', () {
    final monitors = ScreenShareCapture.filterMonitors(devices);
    expect(monitors.map((m) => m.id), ['b', 'c']);
  });

  test('保存した選択が有ればそれ、無ければ先頭、候補が無ければnull', () {
    final monitors = ScreenShareCapture.filterMonitors(devices);
    expect(ScreenShareCapture.pickMonitor(monitors, 'c')?.id, 'c');
    expect(ScreenShareCapture.pickMonitor(monitors, 'gone')?.id, 'b');
    expect(ScreenShareCapture.pickMonitor(monitors, null)?.id, 'b');
    expect(ScreenShareCapture.pickMonitor(const [], 'b'), isNull);
  });
}
