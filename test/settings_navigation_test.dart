import 'package:daidai/features/settings/settings_tab.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/terminology_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/models/send_key_mode.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:daidai/providers/terminology_style_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 設定タブのマルチカラム表示（アカウント＞セキュリティ＞パスワード のような
// 3階層で、深く潜るほど右に列が増えていく表示）が、内側のListView
// （例: 色フォルダのアクセントカラーピッカー）を含めてクラッシュせずに
// 描画・行き来できることを確認する回帰テスト。
// _NodeDetailの高さ制約（Expanded/mainAxisSize）を誤ると、ネストした
// ListViewが無限高さ制約でクラッシュするため、それを実際に踏んで検証する。
//
// マルチカラム表示は列が増えるほど横幅を必要とするため、デフォルトの
// テストサーフェス（800x600）だと3階層目が画面外（横スクロール領域の外）
// に押し出されタップできない。実際の想定利用シーン（広いデスクトップ画面）
// に合わせ、十分広いサーフェスサイズを明示的に指定する。
Future<void> _pumpSettingsTab(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialTerminologyStyleProvider.overrideWithValue(
          TerminologyStyle.worldview,
        ),
        initialAccentColorProvider.overrideWithValue(
          const Color(0xFFF08300),
        ),
        initialSendKeyModeProvider.overrideWithValue(
          SendKeyMode.enterToSend,
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SettingsTab(
            currentUser: AppUser(userId: 'u1', rhingId: 'taro'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('アカウント＞Rhing IDで値が表示される', (tester) async {
    await _pumpSettingsTab(tester);

    await tester.tap(find.text('アカウント'));
    await tester.pumpAndSettle();

    expect(find.text('Rhing ID'), findsOneWidget);
    await tester.tap(find.text('Rhing ID'));
    await tester.pumpAndSettle();

    expect(find.text('@taro'), findsOneWidget);
  });

  testWidgets('アカウント＞セキュリティ＞パスワードまで3階層潜ると、3つの列が同時に表示される', (
    tester,
  ) async {
    await _pumpSettingsTab(tester);

    await tester.tap(find.text('アカウント'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('セキュリティ'));
    await tester.pumpAndSettle();

    // マルチカラム表示なので、アカウント配下の項目（1列目）と
    // セキュリティ配下の項目（2列目）が同時に画面上に残っている。
    expect(find.text('プロフィール名'), findsOneWidget);
    expect(find.text('パスワード'), findsOneWidget);
    expect(find.text('2段階認証'), findsOneWidget);
    expect(find.text('パスキー'), findsOneWidget);

    await tester.tap(find.text('パスワード'));
    await tester.pumpAndSettle();
    expect(find.text('準備中'), findsOneWidget);

    // 別の階層（アプリケーション）に切り替えると、それより深い列は消える。
    await tester.tap(find.text('アプリケーション'));
    await tester.pumpAndSettle();
    expect(find.text('プロフィール名'), findsNothing);
    expect(find.text('パスワード'), findsNothing);
  });

  testWidgets('アプリケーション＞色で既存のアクセントカラーピッカーが表示される（内側ListViewがクラッシュしない）', (
    tester,
  ) async {
    await _pumpSettingsTab(tester);

    await tester.tap(find.text('アプリケーション'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('色'));
    await tester.pumpAndSettle();

    expect(find.text('アクセントカラー'), findsOneWidget);
    expect(find.text('プリセット'), findsOneWidget);
  });

  testWidgets('アプリケーション＞言語で用語スタイルを切り替えられる', (tester) async {
    await _pumpSettingsTab(tester);

    await tester.tap(find.text('アプリケーション'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('言語'));
    await tester.pumpAndSettle();

    expect(find.text('世界観重視'), findsOneWidget);
    expect(find.text('利便性重視'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.text('利便性重視')),
    );
    expect(
      container.read(terminologyStyleProvider),
      TerminologyStyle.worldview,
    );

    await tester.tap(find.text('利便性重視'));
    await tester.pumpAndSettle();

    expect(
      container.read(terminologyStyleProvider),
      TerminologyStyle.convenience,
    );
  });
}
