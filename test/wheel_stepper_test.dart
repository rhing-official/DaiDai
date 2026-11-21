import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/utils/wheel_stepper.dart';

void main() {
  final t0 = DateTime(2026, 11, 21, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('1回が小さい入力でも、足し合わせて1つ進む', () {
    final w = WheelStepper(threshold: 60);
    var steps = 0;
    for (var i = 0; i < 30; i++) {
      steps += w.feed(3, at(i * 10)); // 3px×30 = 90px
    }
    expect(steps, 1);
  });

  test('1回の大きな入力（マウスホイール）で、すぐ1つ進む', () {
    final w = WheelStepper();
    expect(w.feed(100, at(0)), 1);
    expect(w.feed(-100, at(500)), -1);
  });

  test('進めた直後は、慣性の余りで続けて進まない', () {
    final w = WheelStepper(cooldown: const Duration(milliseconds: 160));
    expect(w.feed(100, at(0)), 1);
    expect(w.feed(100, at(50)), 0);
    expect(w.feed(100, at(200)), 1);
  });

  test('向きが変わったら足し合わせをやり直す', () {
    final w = WheelStepper(threshold: 60);
    expect(w.feed(40, at(0)), 0);
    expect(w.feed(-40, at(20)), 0);
    expect(w.feed(-40, at(40)), -1);
  });

  test('入力が途切れたら足し合わせをやり直す', () {
    final w = WheelStepper(threshold: 60);
    expect(w.feed(40, at(0)), 0);
    expect(w.feed(40, at(1000)), 0);
  });
}
