import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/chat/mention_suggestion_list.dart';
import 'package:daidai/l10n/strings.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/utils/mention_suggestion.dart';

List<MentionCandidate> _candidates(int n) => [
  for (var i = 0; i < n; i++)
    MentionCandidate(
      kind: MentionKind.user,
      id: 'u$i',
      label: 'メンバー$i',
      subtitle: 'seed$i',
    ),
];

Widget _host(Strings strings, List<MentionCandidate> c, int selected) =>
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MentionSuggestionList(
            candidates: c,
            selectedIndex: selected,
            onPick: (_) {},
            strings: strings,
            plazaLabel: '広場',
          ),
        ),
      ),
    );

void main() {
  testWidgets('選択を下へ動かすと、選んでいる行が見える位置まで一覧も動く', (tester) async {
    final strings = ProviderContainer(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
      ],
    ).read(appStringsProvider);
    final c = _candidates(30);
    await tester.pumpWidget(_host(strings, c, 0));
    final list = tester.getRect(find.byType(ListView));

    // 先頭付近は見えているが、30件目は一覧の外（スクロールしていないので描画領域外）。
    for (var i = 1; i < 30; i++) {
      await tester.pumpWidget(_host(strings, c, i));
      await tester.pumpAndSettle();
      final row = tester.getRect(find.text('メンバー$i'));
      expect(
        row.top >= list.top - 1 && row.bottom <= list.bottom + 1,
        isTrue,
        reason: '$i件目が一覧の表示範囲内にある',
      );
    }

    // 先頭へ戻る（循環）と、一番上までスクロールが戻る。
    await tester.pumpWidget(_host(strings, c, 0));
    await tester.pumpAndSettle();
    final first = tester.getRect(find.text('メンバー0'));
    expect(first.top >= list.top - 1, isTrue);
  });
}
