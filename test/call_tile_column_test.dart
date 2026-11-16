import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/call/call_tile_layout.dart';

void main() {
  testWidgets('CallTileColumnは、タイルを縦1列で同じ高さに並べる', (tester) async {
    Widget tile(String name) =>
        ColoredBox(color: Colors.grey, child: Text(name));
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 600,
          child: CallTileColumn(tiles: [tile('共有'), tile('自分'), tile('相手')]),
        ),
      ),
    );
    final a = tester.getTopLeft(find.text('共有'));
    final b = tester.getTopLeft(find.text('自分'));
    final c = tester.getTopLeft(find.text('相手'));
    expect(a.dy < b.dy && b.dy < c.dy, isTrue);
    expect(a.dx, b.dx);
    expect(b.dx, c.dx);
    expect(
      (tester.getSize(find.byType(ColoredBox).at(1)).height -
              tester.getSize(find.byType(ColoredBox).at(2)).height)
          .abs(),
      lessThan(0.5),
    );
  });
}
