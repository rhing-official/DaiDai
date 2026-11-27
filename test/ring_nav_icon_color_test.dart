import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/selection_motion_provider.dart';
import 'package:daidai/widgets/nav_chip.dart';

/// 囲みのメニューチップ: アイコンの色は、囲みの丸が重なる割合に連動する（2026-11-27）。選択が
/// 変わった瞬間に塗りの反対色へ変えると、丸がまだ着いていない間、アイコンが背景に溶けて消えた。
Color _iconColor(WidgetTester tester) =>
    tester.widget<Icon>(find.byType(Icon)).color!;

Widget _chip(double? position, {required bool selected}) {
  Widget chip = NavChip(
    icon: Icons.search,
    iconSize: 24,
    label: '検索',
    selected: selected,
    popped: false,
    vertical: false,
    onTap: () {},
    ringIndex: 1,
  );
  if (position != null) {
    chip = RingBarPosition(position: position, child: chip);
  }
  return ProviderScope(
    overrides: [
      initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
      initialAccentColorProvider.overrideWithValue(const Color(0xFF3D2EE0)),
      initialSelectionMotionProvider.overrideWithValue(SelectionMotion.ring),
    ],
    child: MaterialApp(
      home: Scaffold(body: Center(child: chip)),
    ),
  );
}

void main() {
  testWidgets('丸がまだ着いていない（遠い）間は、選択中でも、白い反対色にならない', (tester) async {
    await tester.pumpWidget(_chip(0, selected: true));
    final far = _iconColor(tester);
    await tester.pumpWidget(_chip(1, selected: true));
    final arrived = _iconColor(tester);
    expect(far, isNot(arrived));
    // 着いた時は、塗りの反対色（onPrimary）。
    final context = tester.element(find.byType(NavChip));
    expect(arrived, Theme.of(context).colorScheme.onPrimary);
    // 遠い（丸が1つ分離れている）間は、普通のアイコンの色のまま。
    expect(far, Theme.of(context).colorScheme.onSurfaceVariant);
  });

  testWidgets('丸が滑る途中は、色が中間になる（出て行く側も、同じ）', (tester) async {
    await tester.pumpWidget(_chip(0.5, selected: false));
    final half = _iconColor(tester);
    final context = tester.element(find.byType(NavChip));
    final scheme = Theme.of(context).colorScheme;
    expect(half, Color.lerp(scheme.onSurfaceVariant, scheme.onPrimary, 0.5));
  });

  testWidgets('帯が無い時は、選択中かどうかで決める', (tester) async {
    await tester.pumpWidget(_chip(null, selected: true));
    final context = tester.element(find.byType(NavChip));
    expect(_iconColor(tester), Theme.of(context).colorScheme.onPrimary);
  });
}
