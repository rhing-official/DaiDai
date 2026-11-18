import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/call/call_ring_ripple.dart';
import 'package:daidai/providers/ring_launch_provider.dart';

void main() {
  testWidgets('activeなら波紋（CustomPaint）を出し、falseなら出さない', (tester) async {
    Widget host(bool active) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: CallRingRipple(
            radius: 28,
            active: active,
            child: const CircleAvatar(radius: 28),
          ),
        ),
      ),
    );

    await tester.pumpWidget(host(true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.descendant(
        of: find.byType(CallRingRipple),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );

    await tester.pumpWidget(host(false));
    expect(
      find.descendant(
        of: find.byType(CallRingRipple),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    expect(find.byType(CircleAvatar), findsOneWidget);
  });

  test('RingLaunch.fromChannel: callIdが無ければnull、あれば値を読む', () {
    expect(RingLaunch.fromChannel(null), isNull);
    expect(RingLaunch.fromChannel({'kind': 'dm'}), isNull);
    final ring = RingLaunch.fromChannel({
      'kind': 'group',
      'callId': 'c1',
      'groupId': 'g1',
      'callerName': 'みかん',
      'isVideo': true,
    })!;
    expect(ring.isGroup, isTrue);
    expect(ring.callId, 'c1');
    expect(ring.callerName, 'みかん');
    expect(ring.isVideo, isTrue);
  });
}
