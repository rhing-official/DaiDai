import 'package:daidai/features/settings/settings_tab.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/terminology_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/message_time_format.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/models/send_key_mode.dart';
import 'package:daidai/providers/message_time_format_provider.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:daidai/providers/terminology_style_provider.dart';
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
        initialTerminologyStyleProvider.overrideWithValue(
          TerminologyStyle.worldview,
        ),
        initialAccentColorProvider.overrideWithValue(
          const Color(0xFFF08300),
        ),
        initialSendKeyModeProvider.overrideWithValue(
          SendKeyMode.enterToSend,
        ),
        initialMessageTimeFormatProvider.overrideWithValue(
          MessageTimeFormat.h24,
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
        initialTerminologyStyleProvider.overrideWithValue(
          TerminologyStyle.worldview,
        ),
        initialAccentColorProvider.overrideWithValue(
          const Color(0xFFF08300),
        ),
        initialSendKeyModeProvider.overrideWithValue(
          SendKeyMode.enterToSend,
        ),
        initialMessageTimeFormatProvider.overrideWithValue(
          MessageTimeFormat.h24,
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
    expect(find.text('アカウントの削除'), findsOneWidget);
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
    expect(find.text('表示言語'), findsOneWidget);
    expect(find.text('世界観重視'), findsOneWidget);
    expect(find.text('利便性重視'), findsOneWidget);
  });

  testWidgets('アプリケーションページで用語スタイルを切り替えられる', (tester) async {
    await _pumpSettingsTab(tester);

    await tester.tap(find.text('アプリケーション'));
    await tester.pumpAndSettle();

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

  testWidgets('狭い画面のドリルダウン中に横スワイプで隣接カテゴリへ切り替えられる（回帰テスト）', (
    tester,
  ) async {
    await _pumpSettingsTabNarrow(tester);

    // カテゴリ一覧から「アプリケーション」（アカウント→アプリケーション→
    // 入力→通知の2番目）へドリルダウンする。
    await tester.tap(find.text('アプリケーション'));
    await tester.pumpAndSettle();
    expect(find.text('アクセントカラー'), findsOneWidget);

    // 左スワイプで次のカテゴリ（入力）へ。
    await tester.fling(find.byType(SwipeBackDetector), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('アクセントカラー'), findsNothing);
    expect(find.text('メッセージの送信キー'), findsOneWidget);

    // 右スワイプで前のカテゴリ（アプリケーション）へ戻る。
    await tester.fling(find.byType(SwipeBackDetector), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('アクセントカラー'), findsOneWidget);

    // さらに右スワイプで前のカテゴリ（アカウント）へ。
    await tester.fling(find.byType(SwipeBackDetector), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Rhing ID'), findsOneWidget);

    // 先頭カテゴリで右スワイプすると、従来通りカテゴリ一覧に戻る。
    await tester.fling(find.byType(SwipeBackDetector), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(SwipeBackDetector), findsNothing);
  });
}
