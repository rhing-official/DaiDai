import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/widgets/liquid_sim.dart';

void main() {
  test('5つ跨いでも、途中に水を取り残さず、最後の1つだけが満水になる', () {
    final sim = LiquidSim()
      ..rects = [
        for (var i = 0; i < 6; i++) Rect.fromLTWH(i * 70.0, 0, 56, 56),
      ];
    sim.fillInstantly(0);
    sim.startTransition(0, 5);
    var active = true;
    for (var f = 0; f < 600 && active; f++) {
      active = sim.step(1 / 60);
    }
    for (var i = 0; i < 5; i++) {
      expect(sim.tank(i).water.total, lessThan(0.5), reason: '項目$i');
    }
    expect(sim.tank(5).water.level, greaterThan(0.97));
  });
}
