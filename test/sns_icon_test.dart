import 'package:daidai/models/profile_material.dart';
import 'package:daidai/utils/sns_icon.dart';
import 'package:daidai/widgets/profile_card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('主要サービスは末尾一致でアイコンが決まる', () {
    expect(snsIconNameFor('https://x.com/foo'), 'x');
    expect(snsIconNameFor('https://twitter.com/foo'), 'x');
    expect(snsIconNameFor('https://www.note.com/foo'), 'note');
    expect(snsIconNameFor('https://m.youtube.com/watch?v=1'), 'youtube');
    expect(snsIconNameFor('https://youtu.be/abc'), 'youtube');
    expect(snsIconNameFor('https://gist.github.com/a'), 'github');
    expect(snsIconNameFor('https://BSKY.app/profile/a'), 'bluesky');
  });

  test('別ドメイン・パース不可・空はアイコンなし', () {
    expect(snsIconNameFor('https://notex.com/a'), isNull);
    expect(snsIconNameFor('https://fakex.com/a'), isNull);
    expect(snsIconNameFor('https://x.com.evil.example/a'), isNull);
    expect(snsIconNameFor('https://example.com'), isNull);
    expect(snsIconNameFor('not a url'), isNull);
    expect(snsIconNameFor(''), isNull);
    expect(snsIconAssetFor('https://example.com'), isNull);
    expect(snsIconAssetFor('https://x.com/a'), 'assets/sns_icons/x.svg');
  });

  testWidgets('カード内のURLは、対応サービスはアイコンだけ・対応外は文字', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SnsLinksInline(
            links: [
              SnsLink(id: '1', url: 'https://x.com/a'),
              SnsLink(id: '2', url: 'https://example.com/b'),
            ],
            fontSize: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
    // 対応サービスはアイコンだけ（文字は出さない）、対応外はドメインの文字。
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('x.com'), findsNothing);
    expect(find.text('example.com'), findsOneWidget);
  });
}
