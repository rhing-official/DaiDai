import 'package:daidai/widgets/invite_link_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 招待リンク以外は何も開かず`false`（従来どおり外部で開く）。招待リンクはポップアップを開く
/// （2026-11-09）。
void main() {
  testWidgets('招待リンク以外はポップアップを開かない', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      await openInviteLinkDialog(captured, 'https://example.com/a'),
      isFalse,
    );
    expect(
      await openInviteLinkDialog(captured, 'https://daidai.rhing.jp/settings'),
      isFalse,
    );
    expect(find.byType(Dialog), findsNothing);
  });
}
