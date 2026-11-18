import 'dart:io';

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
    expect(snsIconNameFor('https://gist.github.com/a'), 'github');
    expect(snsIconNameFor('https://BSKY.app/profile/a'), 'bluesky');
  });

  test('YouTubeは、チャンネルのURLのときだけアイコンが出る', () {
    expect(snsIconNameFor('https://www.youtube.com/@foo'), 'youtube');
    expect(snsIconNameFor('https://m.youtube.com/@Foo/videos'), 'youtube');
    expect(snsIconNameFor('https://youtube.com/channel/UCabc'), 'youtube');
    expect(snsIconNameFor('https://youtube.com/c/foo'), 'youtube');
    expect(snsIconNameFor('https://youtube.com/user/foo'), 'youtube');
    // 動画・再生リスト・ショート・ライブ・短縮URL・トップは、チャンネルではない。
    expect(snsIconNameFor('https://m.youtube.com/watch?v=1'), isNull);
    expect(snsIconNameFor('https://youtu.be/abc'), isNull);
    expect(snsIconNameFor('https://youtube.com/playlist?list=1'), isNull);
    expect(snsIconNameFor('https://youtube.com/shorts/abc'), isNull);
    expect(snsIconNameFor('https://youtube.com/live/abc'), isNull);
    expect(snsIconNameFor('https://youtube.com'), isNull);
    expect(snsIconAssetFor('https://youtu.be/abc'), isNull);
  });

  test('別ドメイン・パース不可・空はアイコンなし', () {
    expect(snsIconNameFor('https://notex.com/a'), isNull);
    expect(snsIconNameFor('https://fakex.com/a'), isNull);
    expect(snsIconNameFor('https://x.com.evil.example/a'), isNull);
    expect(snsIconNameFor('https://example.com'), isNull);
    expect(snsIconNameFor('not a url'), isNull);
    expect(snsIconNameFor(''), isNull);
    expect(snsIconAssetFor('https://example.com'), isNull);
  });

  test('ロゴは公式素材を同梱しているサービスだけ。背景の明るさで黒／白を切り替える', () {
    expect(
      snsIconAssetFor('https://bsky.app/profile/a'),
      'assets/sns_icons/bluesky.svg',
    );
    expect(
      snsIconAssetFor('https://bsky.app/profile/a', onDark: true),
      'assets/sns_icons/bluesky-white.svg',
    );
    expect(
      snsIconAssetFor('https://github.com/a', onDark: true),
      'assets/sns_icons/github-white.svg',
    );
    expect(
      snsIconAssetFor('https://discord.gg/abc'),
      'assets/sns_icons/discord.svg',
    );
    expect(
      snsIconAssetFor('https://zenn.dev/a', onDark: true),
      'assets/sns_icons/zenn-white.svg',
    );
    // 公式素材をまだ同梱していないサービスは、対応表にあってもアイコンを出さない。
    expect(snsIconNameFor('https://x.com/a'), 'x');
    expect(snsIconAssetFor('https://x.com/a'), isNull);
    expect(snsIconAssetFor('https://www.youtube.com/@foo'), isNull);
    expect(snsIconAssetFor('https://note.com/a'), isNull);
    // 同梱するロゴの実ファイルが、全てアセットとして存在する。
    for (final name in kSnsOfficialIconNames) {
      expect(File('assets/sns_icons/$name.svg').existsSync(), isTrue);
      expect(File('assets/sns_icons/$name-white.svg').existsSync(), isTrue);
    }
  });

  testWidgets('カード内のURLは、対応サービスはアイコンだけ・対応外は文字', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SnsLinksInline(
            links: [
              SnsLink(id: '1', url: 'https://bsky.app/profile/a'),
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
    expect(find.text('bsky.app'), findsNothing);
    expect(find.text('example.com'), findsOneWidget);
  });
}
