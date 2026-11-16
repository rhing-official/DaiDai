import 'package:daidai/features/call/call_control_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bar({required bool isVideo}) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 600,
        child: CallControlBar(
          isGekiga: false,
          isGlass: false,
          enabled: true,
          muted: false,
          onToggleMute: () {},
          speakerOn: false,
          onToggleSpeaker: () {},
          showSpeakerToggle: false,
          switchingCallType: false,
          onToggleVideoType: () {},
          isVideo: isVideo,
          hasMultipleCameras: true,
          switchingCamera: false,
          onSwitchCamera: () {},
          onHangUp: () {},
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('ビデオがオフの間は、カメラ前後切り替えのボタンを枠ごと詰める', (t) async {
    await t.pumpWidget(_bar(isVideo: false));
    expect(find.byIcon(Icons.cameraswitch), findsNothing);
    final off = t.widgetList(find.byType(Expanded)).length;

    await t.pumpWidget(_bar(isVideo: true));
    expect(find.byIcon(Icons.cameraswitch), findsOneWidget);
    expect(t.widgetList(find.byType(Expanded)).length, off + 1);
  });
}
