import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/group_profile_card.dart';
import 'package:daidai/models/link_preview.dart';
import 'package:daidai/providers/link_preview_provider.dart';
import 'package:daidai/widgets/group_profile_card_view.dart';
import 'package:daidai/widgets/link_preview_card.dart';
import 'package:daidai/widgets/profile_card_view.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 招待リンクのチャット内のカードは、画像ではなくプロフィールカードそのものを描く
/// （背景・アイコンのGIFが動く、2026-11-09）。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, LinkPreview preview) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAccentColorProvider.overrideWithValue(const Color(0xFF3D2EE0)),
          initialAccentColorsByStyleProvider.overrideWithValue(const {}),
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
          linkPreviewProvider.overrideWith((ref, url) async => preview),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LinkPreviewCard(
              url: 'https://daidai.rhing.jp/invite/alice',
              isGekiga: false,
              isMe: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('個人の招待は、プロフィールカードを描く（画像は`Image`で読むのでGIFが再生される）', (tester) async {
    const user = AppUser(userId: 'u1', rhingSeed: 'alice');
    await pump(tester, const LinkPreview(url: 'x', inviteUser: user));
    expect(find.byType(ProfileCardView), findsOneWidget);
  });

  testWidgets('広場の招待は、広場のプロフィールカードを描く', (tester) async {
    await pump(
      tester,
      const LinkPreview(
        url: 'x',
        inviteGroup: GroupProfileCard(name: '広場'),
      ),
    );
    expect(find.byType(GroupProfileCardView), findsOneWidget);
  });
}
