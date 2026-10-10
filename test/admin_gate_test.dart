import 'package:daidai/features/admin/admin_gate.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({required bool isAdmin}) {
  return ProviderScope(
    overrides: [isAdminProvider.overrideWith((ref) async => isAdmin)],
    child: MaterialApp(
      home: AdminGate(
        currentUser: AppUser(userId: 'u1', rhingSeed: 'seed'),
      ),
    ),
  );
}

void main() {
  testWidgets('非管理者には「404 美術館」を見せ、管理画面・登録ボタンは出さない', (tester) async {
    await tester.pumpWidget(_app(isAdmin: false));
    await tester.pumpAndSettle();
    // 未定義URLと同じ「404 美術館」を表示する。
    expect(find.text('404 MUSEUM'), findsOneWidget);
    expect(find.text('トップページへ戻る'), findsOneWidget);
    expect(find.text('権限がありません。'), findsNothing);
    expect(find.text('初回管理者として登録'), findsNothing);
  });
}
