import 'package:daidai/widgets/gekiga/gekiga_panel_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('幅が有限な親の中では、折り返せる長いsubtitleがオーバーフローせず折り返される'
      '（回帰テスト、GekigaPanelBox/GekigaMenuTile廃止前からの既存シナリオ）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: GekigaJointedTileList(
              seeds: const [1],
              selectedFlags: const [false],
              children: [
                GekigaTileContent(
                  leading: const Icon(Icons.radio_button_checked),
                  title: const Text('Ctrl+Enterで送信'),
                  subtitle: const Text('Ctrl+Shift+Enterで相手に通知せず送信'),
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('幅無制限の親（横方向SingleChildScrollView）の中でも例外が出ない'
      '（一対/広場切り替えタブ=GekigaJointedPairの実際の使われ方の回帰テスト）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: GekigaJointedPair(
              leftSeed: 1,
              leftSelected: true,
              left: GekigaTileContent(
                selected: true,
                leading: const Icon(Icons.forum_outlined),
                title: const Text('一対 0'),
                onTap: () {},
              ),
              rightSeed: 2,
              rightSelected: false,
              right: GekigaTileContent(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('広場 0'),
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('ListView相当の文脈でも文字量に応じた可変幅になり、左端が揃う', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 600,
            child: SingleChildScrollView(
              child: GekigaJointedTileList(
                seeds: const [1, 2],
                selectedFlags: const [false, false],
                children: [
                  GekigaTileContent(
                    leading: const Icon(Icons.person),
                    title: const Text('短'),
                    onTap: () {},
                  ),
                  GekigaTileContent(
                    leading: const Icon(Icons.person),
                    title: const Text('とても長いタイトルの相手の名前です'),
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    final boxes = tester.renderObjectList<RenderBox>(
      find.byType(GekigaTileContent),
    );
    final sizes = boxes.map((b) => b.size.width).toList();
    final topLefts = boxes.map((b) => b.localToGlobal(Offset.zero).dx).toList();

    expect(sizes, hasLength(2));
    // 短いタイトルの箱の方が、長いタイトルの箱より明確に幅が狭い
    // （＝行全幅に引き伸ばされず、文字量に応じた可変幅になっている。
    // 短い方の箱に合わせて長い方が縮まる/伸びるようなこともない）。
    expect(sizes[0], lessThan(sizes[1] - 100));
    // 左端（x座標）は両方とも同じ＝左揃えになっている。
    expect(topLefts[0], equals(topLefts[1]));
  });

  testWidgets('GekigaJointedPairは2つの子を接合せず、間に一定の間隔を空けて横に並べる', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: GekigaJointedPair(
              leftSeed: 1,
              leftSelected: false,
              left: GekigaTileContent(
                leading: const Icon(Icons.forum_outlined),
                title: const Text('一対'),
                onTap: () {},
              ),
              rightSeed: 2,
              rightSelected: false,
              right: GekigaTileContent(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('広場'),
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    final boxes = tester.renderObjectList<RenderBox>(
      find.byType(GekigaTileContent),
    );
    final rects = boxes
        .map((b) => b.localToGlobal(Offset.zero) & b.size)
        .toList();

    expect(rects, hasLength(2));
    // 接合を廃止したため、右の子の左端は左の子の右端に一致せず、一定の
    // 間隔（`_RenderGekigaJointedList._gap` = 8px）だけ空く。
    expect(rects[1].left, moreOrLessEquals(rects[0].right + 8, epsilon: 0.01));
  });

  testWidgets('GekigaJointedTileList内の各子のonTapは独立して反応する', (tester) async {
    var tappedIndex = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GekigaJointedTileList(
            seeds: const [1, 2],
            selectedFlags: const [false, false],
            children: [
              GekigaTileContent(
                leading: const Icon(Icons.person),
                title: const Text('1件目'),
                onTap: () => tappedIndex = 0,
              ),
              GekigaTileContent(
                leading: const Icon(Icons.person),
                title: const Text('2件目'),
                onTap: () => tappedIndex = 1,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('2件目'));
    expect(tappedIndex, 1);
  });
}
