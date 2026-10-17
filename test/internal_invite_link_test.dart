import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/link_preview.dart';
import 'package:daidai/models/user_invite_preview.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/link_preview_provider.dart';
import 'package:daidai/widgets/link_preview_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 招待リンクも汎用のリンクプレビュー（題・説明・画像）で出す（2026-10-17、
// 専用のアプリ内カードと呼びかけ文は廃止）。DaiDai自身のドメインは表記しない。

Future<void> _pumpCard(
  WidgetTester tester,
  String url, {
  bool isGekiga = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        linkPreviewProvider.overrideWith(
          (ref, url) async => LinkPreview(
            url: url,
            title: '新（@aaa）',
            description: 'DaiDaiで仲間になりましょう',
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: LinkPreviewCard(url: url, isGekiga: isGekiga, isMe: false),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final isGekiga in [false, true]) {
    for (final path in ['invite/aaa/00d9b92b', 'join/g1/00d9b92b']) {
      testWidgets('DaiDai自身の招待リンクのプレビューは題と説明を出し、ドメインは表記しない'
          '（$path、劇画=$isGekiga）', (tester) async {
        await _pumpCard(
          tester,
          'https://daidai.rhing.jp/$path',
          isGekiga: isGekiga,
        );
        expect(find.text('新（@aaa）'), findsOneWidget);
        expect(find.text('DaiDaiで仲間になりましょう'), findsOneWidget);
        expect(find.text('daidai.rhing.jp'), findsNothing);
      });
    }
  }

  testWidgets('外部サイトのリンクにはドメインを表記する', (tester) async {
    await _pumpCard(tester, 'https://example.com/page');
    expect(find.text('example.com'), findsOneWidget);
  });

  test('招待リンクの版識別子は内容が同じなら同じ、変わると別の値になる', () {
    const a = UserInvitePreview(userId: 'u1', nickname: '新', iconUrl: 'x');
    const same = UserInvitePreview(userId: 'u1', nickname: '新', iconUrl: 'x');
    const changed = UserInvitePreview(
      userId: 'u1',
      nickname: '新',
      iconUrl: 'x',
      layoutPreset: 'center',
    );
    expect(a.version, same.version);
    expect(a.version, isNot(changed.version));
    expect(a.version, matches(RegExp(r'^[0-9a-f]{8}$')));
  });

  test('リンク更新用の値（linkSalt）が変わると、内容が同じでも版識別子が変わる', () {
    const base = UserInvitePreview(userId: 'u1', nickname: '新');
    const refreshed = UserInvitePreview(
      userId: 'u1',
      nickname: '新',
      linkSalt: 1700000000000,
    );
    const refreshedAgain = UserInvitePreview(
      userId: 'u1',
      nickname: '新',
      linkSalt: 1700000000001,
    );
    expect(base.version, isNot(refreshed.version));
    expect(refreshed.version, isNot(refreshedAgain.version));
    // Firestoreに保存する内容（toJson）にはsaltを含めない。
    expect(refreshed.toJson().containsKey('linkSalt'), isFalse);
  });
}
