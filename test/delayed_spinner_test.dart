import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/widgets/delayed_spinner.dart';

void main() {
  testWidgets('1秒たつまでは何も出さず、過ぎるとスピナーを出す', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DelayedSpinner())),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('時間内に取り除かれてもエラーにならない', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DelayedSpinner())),
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
