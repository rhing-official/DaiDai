import 'package:daidai/models/profile_card.dart';
import 'package:daidai/widgets/profile_card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _card({CardLayoutPreset? preset, CardTextAlign? align}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: ProfileCardView(
        width: 400,
        height: 500,
        nickname: 'ニック',
        statusMessage: '一言',
        layoutPreset: preset,
        textAlign: align,
      ),
    ),
  ),
);

void main() {
  group('ProfileCard 配置プリセット', () {
    test('既存データ（キー無し）はnullで読め、既定のままならキーを出さない', () {
      final legacy = ProfileCard.fromJson({'id': 'c', 'name': 'n'});
      expect(legacy.layoutPreset, isNull);
      expect(legacy.textAlign, isNull);
      final json = legacy.toJson();
      expect(json.containsKey('layoutPreset'), isFalse);
      expect(json.containsKey('textAlign'), isFalse);
    });

    test('JSON往復・不明な値のフォールバック・clear', () {
      final card = ProfileCard(
        id: 'c',
        name: 'n',
        layoutPreset: CardLayoutPreset.center,
        textAlign: CardTextAlign.end,
      );
      final restored = ProfileCard.fromJson(card.toJson());
      expect(restored.layoutPreset, CardLayoutPreset.center);
      expect(restored.textAlign, CardTextAlign.end);
      final bad = ProfileCard.fromJson({
        'id': 'c',
        'name': 'n',
        'layoutPreset': 'zzz',
        'textAlign': 3,
      });
      expect(bad.layoutPreset, isNull);
      expect(bad.textAlign, isNull);
      final cleared = restored.copyWith(
        clearLayoutPreset: true,
        clearTextAlign: true,
      );
      expect(cleared.layoutPreset, isNull);
      expect(cleared.textAlign, isNull);
    });
  });

  group('ProfileCardView の配置', () {
    Future<Rect> nicknameRect(WidgetTester tester, Widget w) async {
      await tester.pumpWidget(w);
      return tester.getRect(find.text('ニック'));
    }

    // ブロック全体の位置はアイコン（ブロックで最も幅広）で見る。
    Future<Rect> avatarRect(WidgetTester tester, Widget w) async {
      await tester.pumpWidget(w);
      return tester.getRect(find.byType(ProfileCardAvatar));
    }

    Rect cardRect(WidgetTester tester) =>
        tester.getRect(find.byType(ProfileCardView));

    testWidgets('未指定は左下（従来）', (tester) async {
      final r = await nicknameRect(tester, _card());
      final c = cardRect(tester);
      expect(r.left, lessThan(c.center.dx));
      expect(r.center.dy, greaterThan(c.center.dy));
    });

    testWidgets('プリセットごとに期待する側へ寄る', (tester) async {
      final top = await avatarRect(
        tester,
        _card(preset: CardLayoutPreset.topLeft),
      );
      final c = cardRect(tester);
      expect(top.top, lessThan(c.center.dy - 100));
      expect(top.left, lessThan(c.center.dx));

      final bc = await avatarRect(
        tester,
        _card(preset: CardLayoutPreset.bottomCenter),
      );
      expect(bc.center.dx, closeTo(c.center.dx, 1));
      expect(bc.center.dy, greaterThan(c.center.dy));

      final br = await avatarRect(
        tester,
        _card(preset: CardLayoutPreset.bottomRight),
      );
      expect(br.right, greaterThan(c.center.dx));
      expect(br.center.dy, greaterThan(c.center.dy));

      final mid = await avatarRect(
        tester,
        _card(preset: CardLayoutPreset.center),
      );
      expect(mid.center.dx, closeTo(c.center.dx, 1));
      expect(mid.center.dy, lessThan(c.bottom - 100));
      expect(mid.center.dy, greaterThan(c.top + 100));
    });

    testWidgets('文字の揃えは配置と独立（左下のまま中央揃え）', (tester) async {
      // アイコンが最も幅広いため、呼び名はブロック内で中央に寄る。
      final left = await nicknameRect(tester, _card());
      final centered = await nicknameRect(
        tester,
        _card(align: CardTextAlign.center),
      );
      expect(centered.left, greaterThan(left.left));
      expect(centered.center.dy, closeTo(left.center.dy, 1));
    });
  });
}
