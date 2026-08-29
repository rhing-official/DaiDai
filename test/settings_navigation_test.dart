import 'package:daidai/features/settings/settings_tab.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/chat_layout_style.dart';
import 'package:daidai/models/message_time_format.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/chat_layout_style_provider.dart';
import 'package:daidai/providers/custom_accent_colors_provider.dart';
import 'package:daidai/providers/draft_sync_enabled_provider.dart';
import 'package:daidai/providers/gekiga_background_color_provider.dart';
import 'package:daidai/models/send_key_mode.dart';
import 'package:daidai/models/sticker_send_mode.dart';
import 'package:daidai/providers/message_time_format_provider.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:daidai/providers/sticker_send_mode_provider.dart';
import 'package:daidai/providers/theme_mode_provider.dart';
import 'package:daidai/widgets/swipe_gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 設定タブの2ペイン表示（左にカテゴリ一覧、右に選んだカテゴリの中身を
// 見出し付きセクションとして1ページにまとめて表示する。2026-07-24変更で
// サイドバーの階層を最上位カテゴリの1段だけに留めた）が、内側のListView
// （例: 色セクションのアクセントカラーピッカー）を含めてクラッシュせずに
// 描画・行き来できることを確認する回帰テスト。
//
// 2ペイン表示は十分な横幅を必要とするため、デフォルトのテストサーフェス
// （800x600）だと2ペイン表示のしきい値を満たさない。実際の想定利用シーン
// （広いデスクトップ画面）に合わせ、十分広いサーフェスサイズを明示的に指定する。
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
        initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
        initialCustomAccentColorsProvider.overrideWithValue(const []),
        initialGekigaBackgroundColorProvider.overrideWithValue(
          const Color(0xFFC1272D),
        ),
        initialSendKeyModeProvider.overrideWithValue(SendKeyMode.enterToSend),
        initialStickerSendModeProvider.overrideWithValue(StickerSendMode.line),
        initialDraftSyncEnabledProvider.overrideWithValue(true),
        initialMessageTimeFormatProvider.overrideWithValue(
          MessageTimeFormat.h24,
        ),
        initialChatLayoutStyleProvider.overrideWithValue(
          ChatLayoutStyle.sideBySide,
        ),
        initialAppThemeModeProvider.overrideWithValue(ThemeMode.system),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
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

// 狭い画面（サイドバー+ドリルダウン方式）でのカテゴリ切り替えスワイプの
// 回帰テスト用。760のブレークポイント未満の幅にする。
Future<void> _pumpSettingsTabNarrow(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
        initialCustomAccentColorsProvider.overrideWithValue(const []),
        initialGekigaBackgroundColorProvider.overrideWithValue(
          const Color(0xFFC1272D),
        ),
        initialSendKeyModeProvider.overrideWithValue(SendKeyMode.enterToSend),
        initialStickerSendModeProvider.overrideWithValue(StickerSendMode.line),
        initialDraftSyncEnabledProvider.overrideWithValue(true),
        initialMessageTimeFormatProvider.overrideWithValue(
          MessageTimeFormat.h24,
        ),
        initialChatLayoutStyleProvider.overrideWithValue(
          ChatLayoutStyle.sideBySide,
        ),
        initialAppThemeModeProvider.overrideWithValue(ThemeMode.system),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
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
  testWidgets('既定でアカウントページが選択され、Rhing IDの値が表示される', (tester) async {
    await _pumpSettingsTab(tester);

    // サイドバーからクリックしなくても、既定でアカウントが選ばれている。
    expect(find.text('Rhing ID'), findsOneWidget);
    expect(find.text('@taro'), findsOneWidget);
  });

  testWidgets('アカウントページには各セクションがドリルダウンなしで一度に表示される', (tester) async {
    await _pumpSettingsTab(tester);

    // サイドバーのタイルと内容ペインの見出しの両方に「アカウント」の文字が
    // 出るため、サイドバー側（先に見つかる方）をタップする。
    await tester.tap(find.text('アカウント').first);
    await tester.pumpAndSettle();

    // 旧実装ではセキュリティ配下（パスワード等）を見るには「セキュリティ」を
    // タップしてさらに列を開く必要があったが、現在は最初から1ページに
    // まとまっているため、クリックなしですべて同時に見える。
    expect(find.text('パスワード'), findsOneWidget);
    expect(find.text('2段階認証'), findsOneWidget);
    expect(find.text('パスキー'), findsOneWidget);
    expect(find.text('QRコードによるログイン'), findsOneWidget);
    expect(find.text('ログアウト'), findsOneWidget);
    expect(find.text('アカウントを削除'), findsOneWidget);
    expect(find.text('準備中'), findsWidgets);

    // 別のカテゴリ（アプリケーション）に切り替えると、アカウントの内容は消える。
    await tester.tap(find.text('アプリケーション'));
    await tester.pumpAndSettle();
    expect(find.text('パスワード'), findsNothing);
  });

  testWidgets('アプリケーションページには色・UI・文字・言語セクションが一度に表示される（内側ListViewがクラッシュしない）', (
    tester,
  ) async {
    await _pumpSettingsTab(tester);

    await tester.tap(find.text('アプリケーション'));
    await tester.pumpAndSettle();

    expect(find.text('アクセントカラー'), findsOneWidget);
    expect(find.text('プリセット'), findsOneWidget);
    expect(find.text('文字'), findsOneWidget);

    // UIスタイルの選択肢が3つ（フラット/劇画/デッサン）に増えたことで
    // ページが縦に伸び、「表示言語」がSliverListの遅延構築で最初は
    // マウントされていない（2026-08-25）。2ペイン表示は左のサイドバーも
    // 同時にScrollableのため、既定の「Scrollableを1つだけ探す」挙動と
    // 衝突しないよう、右ページのScrollableを明示して探す。
    final applicationScrollable = find.ancestor(
      of: find.text('アクセントカラー'),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('表示言語'),
      300,
      scrollable: applicationScrollable,
    );
    expect(find.text('表示言語'), findsOneWidget);
  });

  testWidgets('狭い画面のドリルダウン中に左スワイプで次のカテゴリへ切り替え、右スワイプで一覧へ戻る（回帰テスト）', (
    tester,
  ) async {
    await _pumpSettingsTabNarrow(tester);

    // カテゴリ一覧から「アプリケーション」（アカウント→アプリケーション→
    // 語らい→通知の2番目）へドリルダウンする（2026-07-30、入力カテゴリを
    // 廃止して語らいへ統合したため、以前あった「入力」の段は無くなった）。
    await tester.tap(find.text('アプリケーション'));
    await tester.pumpAndSettle();
    expect(find.text('アクセントカラー'), findsOneWidget);

    // 左スワイプで次のカテゴリ（語らい）へ。
    await tester.fling(
      find.byType(SwipeBackDetector),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('アクセントカラー'), findsNothing);
    expect(find.text('ブロックしたユーザー'), findsOneWidget);

    // さらに左スワイプで次のカテゴリ（通知）へ。
    await tester.fling(
      find.byType(SwipeBackDetector),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('ブロックしたユーザー'), findsNothing);
    expect(find.text('準備中'), findsWidgets);

    // 右スワイプすると、隣接カテゴリではなく常にカテゴリ一覧へ戻る。
    await tester.fling(
      find.byType(SwipeBackDetector),
      const Offset(300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.byType(SwipeBackDetector), findsNothing);
    expect(find.text('アプリケーション'), findsOneWidget); // 一覧のカテゴリ名として表示される
  });

  testWidgets('語らいページにはメッセージの表示・送信キー設定も含まれる'
      '（2026-07-30、アプリケーション/入力カテゴリからの統合）', (tester) async {
    // 狭い画面のドリルダウンにする（広い画面の2ペインは左のサイドバーと
    // 右のページが同時にScrollableとなり、scrollUntilVisibleの既定の
    // 「Scrollableを1つだけ探す」挙動と衝突するため）。
    await _pumpSettingsTabNarrow(tester);

    await tester.tap(find.text('語らい'));
    await tester.pumpAndSettle();

    // ブロックしたユーザー・プロフィールカードの各セクションは、テスト環境に
    // Firebaseが初期化されていないためエラー表示になるが、その下に続く
    // メッセージの表示・送信キー設定のセクション自体はそれとは独立して
    // 描画される。ページが縦に長くSliverListの遅延構築で最初は
    // マウントされていないため、scrollUntilVisibleでスクロールしてから探す。
    await tester.scrollUntilVisible(find.text('メッセージの表示'), 300);
    expect(find.text('メッセージの表示'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('メッセージの送信キー'), 300);
    expect(find.text('メッセージの送信キー'), findsOneWidget);

    // 一覧へ戻り（右スワイプ）、アプリケーションページには両方とも
    // もう出てこないことを確認する（見つからない場合の判定はスクロール
    // 位置に依存しないため、ここではscrollUntilVisible不要）。
    await tester.fling(
      find.byType(SwipeBackDetector),
      const Offset(300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('アプリケーション'));
    await tester.pumpAndSettle();
    expect(find.text('メッセージの表示'), findsNothing);
    expect(find.text('メッセージの送信キー'), findsNothing);
  });
}
