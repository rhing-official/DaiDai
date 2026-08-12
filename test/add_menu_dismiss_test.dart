import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// talks_tab.dartの_showAddMenu()が使うshowGeneralDialogの構造を再現した回帰テスト。
// 過去に Center > Material(color: transparent) > Dialog という二重ラップにしたところ、
// 外側のMaterialがタップを吸収し、バリアの外側タップによるdismissが効かなくなっていた。
Future<void> openAddMenuLikeDialog(BuildContext context) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'test',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Center(
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text('一対を始める')),
              ListTile(title: Text('広場を作る')),
            ],
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: curved, child: child),
      );
    },
  );
}

void main() {
  testWidgets('語らいの＋ポップアップは外側タップで閉じる', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => openAddMenuLikeDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('一対を始める'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('一対を始める'), findsNothing);
  });
}
