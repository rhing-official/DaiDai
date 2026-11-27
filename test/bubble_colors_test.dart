import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;

import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/models/dark_variant.dart';
import 'package:daidai/utils/bubble_colors.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance() + 0.05;
  final lb = b.computeLuminance() + 0.05;
  return math.max(la, lb) / math.min(la, lb);
}

void main() {
  paletteTests();
  const backgrounds = <String, Color>{
    'ライト': Color(0xFFF2F2F5),
    'ダーク標準': Color(0xFF121212),
    'ダークやわらかい': Color(0xFF2A2A2D),
    'ダーク黒': Color(0xFF000000),
    '黒板': Color(0xFF2B3A33),
    '紙': Color(0xFFEFE9DD),
  };
  const accents = <String, Color>{
    '既定': Color(0xCC3D2EE0),
    '明るい': Color(0xFFFFE600),
    '暗い': Color(0xFF101040),
  };

  for (final bg in backgrounds.entries) {
    test('相手の吹き出しは、背景（${bg.key}）から離れている', () {
      final other = chatBubbleFill(
        background: bg.value,
        accent: accents['既定']!,
        isMe: false,
      );
      expect(_contrast(bg.value, other), greaterThan(1.15));
    });
    for (final ac in accents.entries) {
      test('自分と相手の塗りが違う（${bg.key}、${ac.key}）', () {
        final mine = chatBubbleFill(
          background: bg.value,
          accent: ac.value,
          isMe: true,
        );
        final other = chatBubbleFill(
          background: bg.value,
          accent: ac.value,
          isMe: false,
        );
        expect(mine, isNot(other));
        expect(mine.a, 1.0);
      });
    }
  }

  test('生成りの強さは、他より小さい離し方になる', () {
    const bg = Color(0xFFEFE9DD);
    final normal = chatBubbleFill(
      background: bg,
      accent: const Color(0xFF3D2EE0),
      isMe: false,
    );
    final soft = chatBubbleFill(
      background: bg,
      accent: const Color(0xFF3D2EE0),
      isMe: false,
      strength: 0.5,
    );
    expect(_contrast(bg, soft), lessThan(_contrast(bg, normal)));
    expect(soft, isNot(bg));
  });
}

void paletteTests() {
  group('背景の明るさの帯', () {
    test('真ん中の明るさは、近い帯の端へ寄る', () {
      final mid = AppearancePalette.normalizeBackground(
        const Color(0xFF808080),
      );
      final l = HSLColor.fromColor(mid).lightness;
      expect(
        l == kDarkBackgroundMaxLightness || l == kLightBackgroundMinLightness,
        isTrue,
      );
    });
    test('帯の中にある色は、そのまま', () {
      const dark = Color(0xFF121212);
      const light = Color(0xFFF2F2F5);
      expect(AppearancePalette.normalizeBackground(dark), dark);
      expect(AppearancePalette.normalizeBackground(light), light);
    });
    test('意匠のパネルの色を渡すと、面の色はそれになる', () {
      const panel = Color(0xFFABCDEF);
      final p = AppearancePalette.fromBackground(
        const Color(0xFFFFFFFF),
        surface: panel,
      );
      expect(p.surface, panel);
    });
    test('どの背景でも、相手の吹き出しは背景から離れる', () {
      for (var i = 0; i <= 255; i += 15) {
        final c = Color.fromARGB(255, i, i, i);
        final p = AppearancePalette.fromBackground(c);
        final bubble = p.bubbleFill(
          isMe: false,
          accent: const Color(0xFF3D2EE0),
        );
        expect(
          (p.background.computeLuminance() - bubble.computeLuminance()).abs(),
          greaterThan(0.02),
          reason: 'bg=$i',
        );
      }
    });
  });
}
