import 'package:daidai/features/chat/room_tab_bar.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 寄合タブバー（アイコンのみのメッセージ画面の上部）が、全てのデザイン×選択の動きで
/// 描画でき、選択の切り替えとタップが働くこと（2026-11-27）。
void main() {
  final rooms = [
    for (var i = 0; i < 8; i++)
      (roomId: 'r$i', name: '寄合の名前$i', unreadCount: i == 3 ? 2 : 0),
  ];

  Widget app({
    required AppUiStyle style,
    required SelectionMotion motion,
    required String selected,
    required void Function(String) onSelect,
  }) {
    return ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
        initialAccentColorsByStyleProvider.overrideWithValue(const {}),
        initialAppUiStyleProvider.overrideWithValue(style),
        initialSelectionMotionProvider.overrideWithValue(motion),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: RoomTabBar(
              rooms: rooms,
              selectedRoomId: selected,
              onSelectRoom: (room) => onSelect(room.roomId),
              maxWidth: 360,
              isGekiga: style == AppUiStyle.gekiga,
              onCreateRoom: (_) async {},
            ),
          ),
        ),
      ),
    );
  }

  for (final style in AppUiStyle.values) {
    for (final motion in SelectionMotion.values) {
      testWidgets('${style.name}×${motion.name}: 描画でき、選択を切り替えられる', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        String? tapped;
        await tester.pumpWidget(
          app(
            style: style,
            motion: motion,
            selected: 'r0',
            onSelect: (id) => tapped = id,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('寄合の名前0'), findsWidgets);

        // 選択を移す（動きの途中まで進めても、最後まで進めても、例外が出ない）。
        await tester.pumpWidget(
          app(
            style: style,
            motion: motion,
            selected: 'r1',
            onSelect: (id) => tapped = id,
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);

        await tester.tap(find.textContaining('寄合の名前0').first);
        expect(tapped, 'r0');
      });
    }
  }
}
