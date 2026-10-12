import 'dart:ui';

import 'package:daidai/models/group_profile_card.dart';
import 'package:daidai/widgets/group_profile_card_view.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/widgets/hover_profile_card.dart';
import 'package:daidai/widgets/user_profile_card_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hoverProfileCardOffset', () {
    const screen = Size(1200, 800);
    const card = Size(260, 325);

    test('基本はタイルの右端の外側に、上端を揃えて置く', () {
      final o = hoverProfileCardOffset(
        tile: const Rect.fromLTWH(100, 200, 300, 60),
        screen: screen,
        card: card,
      );
      expect(o, const Offset(408, 200));
    });

    test('右に収まらなければタイルの左側へ', () {
      final o = hoverProfileCardOffset(
        tile: const Rect.fromLTWH(900, 200, 280, 60),
        screen: screen,
        card: card,
      );
      expect(o.dx, 900 - 8 - 260);
    });

    test('縦は画面内に収める', () {
      final o = hoverProfileCardOffset(
        tile: const Rect.fromLTWH(100, 700, 300, 60),
        screen: screen,
        card: card,
      );
      expect(o.dy, 800 - 8 - 325);
      final top = hoverProfileCardOffset(
        tile: const Rect.fromLTWH(100, -20, 300, 60),
        screen: screen,
        card: card,
      );
      expect(top.dy, 8);
    });
  });

  // 検証（`debugAssertAllFoundationVarsUnset`）はテスト本体の直後に走るため、
  // 本体の中で必ず元に戻す。
  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  group('HoverProfileCard', () {
    const user = AppUser(userId: 'u2', rhingSeed: 'hanako');

    Future<TestGesture> hoverOn(WidgetTester tester) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.byType(SizedBox).first));
      return gesture;
    }

    Widget app() => MaterialApp(
      home: Scaffold(
        body: Center(
          child: HoverProfileCard(
            user: user,
            conversationId: 'dm1',
            child: const SizedBox(width: 200, height: 60),
          ),
        ),
      ),
    );

    testWidgets('コンピューターで0.5秒ホバーするとカードが出て、外れると消える', (tester) async {
      await withPlatform(TargetPlatform.linux, () async {
        await tester.pumpWidget(app());
        final gesture = await hoverOn(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(UserProfileCardView), findsNothing);

        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(UserProfileCardView), findsOneWidget);

        await gesture.moveTo(const Offset(5, 5));
        await tester.pump();
        expect(find.byType(UserProfileCardView), findsNothing);
      });
    });

    testWidgets('0.5秒未満で外れたら出ない', (tester) async {
      await withPlatform(TargetPlatform.linux, () async {
        await tester.pumpWidget(app());
        final gesture = await hoverOn(tester);
        await tester.pump(const Duration(milliseconds: 300));
        await gesture.moveTo(const Offset(5, 5));
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(UserProfileCardView), findsNothing);
      });
    });

    testWidgets('広場はカードが設定されている時だけ出る', (tester) async {
      await withPlatform(TargetPlatform.linux, () async {
        Widget groupApp(GroupProfileCard? card) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: HoverProfileCard.group(
                card: card,
                child: const SizedBox(width: 200, height: 60),
              ),
            ),
          ),
        );
        await tester.pumpWidget(groupApp(null));
        var gesture = await hoverOn(tester);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(GroupProfileCardView), findsNothing);
        await gesture.removePointer();

        await tester.pumpWidget(groupApp(const GroupProfileCard(name: '広場')));
        gesture = await hoverOn(tester);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(GroupProfileCardView), findsOneWidget);
      });
    });

    testWidgets('タッチ端末（モバイルOS）では出ない', (tester) async {
      await withPlatform(TargetPlatform.android, () async {
        await tester.pumpWidget(app());
        await hoverOn(tester);
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(UserProfileCardView), findsNothing);
      });
    });

    testWidgets('クリックで閉じる', (tester) async {
      await withPlatform(TargetPlatform.linux, () async {
        await tester.pumpWidget(app());
        final gesture = await hoverOn(tester);
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(UserProfileCardView), findsOneWidget);
        await gesture.down(tester.getCenter(find.byType(SizedBox).first));
        await gesture.up();
        await tester.pump();
        expect(find.byType(UserProfileCardView), findsNothing);
      });
    });
  });
}
