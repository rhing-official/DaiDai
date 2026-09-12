import 'dart:async' show unawaited;

import 'package:appflowy_editor/appflowy_editor.dart'
    show AppFlowyEditorLocalizations;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'push_notifications.dart';
import 'l10n/app_locale.dart';
import 'models/app_ui_style.dart';
import 'providers/accent_color_provider.dart';
import 'providers/app_locale_provider.dart';
import 'providers/app_ui_style_provider.dart';
import 'providers/calling_sound_provider.dart';
import 'providers/chat_layout_style_provider.dart';
import 'providers/conversation_sort_order_provider.dart';
import 'providers/custom_accent_colors_provider.dart';
import 'providers/draft_sync_enabled_provider.dart';
import 'providers/font_design_provider.dart';
import 'providers/gekiga_background_color_provider.dart';
import 'providers/message_time_format_provider.dart';
import 'providers/notification_sound_provider.dart';
import 'providers/ringtone_sound_provider.dart';
import 'providers/send_key_mode_provider.dart';
import 'providers/sticker_send_mode_provider.dart';
import 'providers/talks_list_layout_style_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'router/app_router.dart';
import 'utils/android_notification_sound_sync.dart';
import 'theme/app_theme.dart';
import 'theme/gekiga/gekiga_theme.dart';
import 'theme/glass/glass_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 劇画UIスタイルの見出しフォント（Anton）はGoogle CDNから実行時取得せず、
  // アプリに同梱したファイルのみを使う（プライバシーファースト方針に
  // 合わせ、外部通信を発生させないため）。
  GoogleFonts.config.allowRuntimeFetching = false;
  // 既定のハッシュURL戦略（例: /#/join/xxx）のままだと、招待リンク
  // （例: https://.../join/xxx/yyy、ハッシュ無し）を新しいタブで直接開いた際に
  // go_routerがURLのパス部分をハッシュとして読み取れず、常にルート（語らい
  // タブ）へフォールバックしてしまっていた（招待リンクを踏んでも語らいが
  // 開くだけで何も起きない不具合の原因）。パスベースのURL戦略に切り替える。
  usePathUrlStrategy();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Firestoreのオフライン永続化キャッシュを有効化する（2026-09-10追加）。
  // 未指定だとWeb版は特にメモリキャッシュのみとなり、画面を離れて購読が
  // 切れるたびに毎回サーバーへ再取得しに行くことになる。webPersistentTabManagerに
  // マルチタブ対応を明示指定し、開発中に複数タブを開く運用（別アカウントでの
  // 動作確認等）でpersistenceが片方だけメモリにフォールバックしないようにする。
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    webPersistentTabManager: WebPersistentMultipleTabManager(),
  );
  // プッシュ通知（Web + Androidのみ、lib/push_notifications.dart参照）。
  // バックグラウンドハンドラの登録・ローカル通知チャンネルの初期化は
  // 認証状態に関わらず一度だけ行う（実際のトークン登録・権限リクエストは
  // ログイン後に`PushNotificationBootstrap`が行う）。
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await initializeLocalNotifications();
  final initialAccentColor = await loadInitialAccentColor();
  final initialCustomAccentColors = await loadInitialCustomAccentColors();
  final initialGekigaBackgroundColor = await loadInitialGekigaBackgroundColor();
  final initialAppLocale = await loadInitialAppLocale();
  final initialSendKeyMode = await loadInitialSendKeyMode();
  final initialStickerSendMode = await loadInitialStickerSendMode();
  final initialDraftSyncEnabled = await loadInitialDraftSyncEnabled();
  final initialMessageTimeFormat = await loadInitialMessageTimeFormat();
  final initialChatLayoutStyle = await loadInitialChatLayoutStyle();
  final initialTalksListLayoutStyle = await loadInitialTalksListLayoutStyle();
  final initialAppThemeMode = await loadInitialAppThemeMode();
  final initialAppUiStyle = await loadInitialAppUiStyle();
  final initialConversationSortOrder = await loadInitialConversationSortOrder();
  final initialFontDesign = await loadInitialFontDesign();
  final initialRingtoneSound = await loadInitialRingtoneSound();
  final initialCallingSound = await loadInitialCallingSound();
  final initialNotificationSound = await loadInitialNotificationSound();
  final initialRingtoneCustomSound = await loadInitialRingtoneCustomSound();
  final initialCallingCustomSound = await loadInitialCallingCustomSound();
  final initialNotificationCustomSound =
      await loadInitialNotificationCustomSound();
  // 他端末で既にアップロード済みのカスタム通知音が同期されてきた場合に
  // 備え、起動のたびにローカルのダウンロード・チャンネル作成状態を確認する
  // （Androidのみ、`ensureCustomNotificationChannelReady`は既に準備済みなら
  // 早期returnするため軽量、2026-09-06 Phase B追加）。
  if (initialNotificationSound != null &&
      initialNotificationSound.startsWith('http')) {
    unawaited(ensureCustomNotificationChannelReady(initialNotificationSound));
  }
  runApp(
    ProviderScope(
      overrides: [
        initialAccentColorProvider.overrideWithValue(initialAccentColor),
        initialCustomAccentColorsProvider.overrideWithValue(
          initialCustomAccentColors,
        ),
        initialGekigaBackgroundColorProvider.overrideWithValue(
          initialGekigaBackgroundColor,
        ),
        initialAppLocaleProvider.overrideWithValue(initialAppLocale),
        initialSendKeyModeProvider.overrideWithValue(initialSendKeyMode),
        initialStickerSendModeProvider.overrideWithValue(
          initialStickerSendMode,
        ),
        initialDraftSyncEnabledProvider.overrideWithValue(
          initialDraftSyncEnabled,
        ),
        initialMessageTimeFormatProvider.overrideWithValue(
          initialMessageTimeFormat,
        ),
        initialChatLayoutStyleProvider.overrideWithValue(
          initialChatLayoutStyle,
        ),
        initialTalksListLayoutStyleProvider.overrideWithValue(
          initialTalksListLayoutStyle,
        ),
        initialAppThemeModeProvider.overrideWithValue(initialAppThemeMode),
        initialAppUiStyleProvider.overrideWithValue(initialAppUiStyle),
        initialConversationSortOrderProvider.overrideWithValue(
          initialConversationSortOrder,
        ),
        initialFontDesignProvider.overrideWithValue(initialFontDesign),
        initialRingtoneSoundProvider.overrideWithValue(initialRingtoneSound),
        initialCallingSoundProvider.overrideWithValue(initialCallingSound),
        initialNotificationSoundProvider.overrideWithValue(
          initialNotificationSound,
        ),
        initialRingtoneCustomSoundProvider.overrideWithValue(
          initialRingtoneCustomSound,
        ),
        initialCallingCustomSoundProvider.overrideWithValue(
          initialCallingCustomSound,
        ),
        initialNotificationCustomSoundProvider.overrideWithValue(
          initialNotificationCustomSound,
        ),
      ],
      child: const DaiDaiApp(),
    ),
  );
  // 完全終了状態（cold start）から通知タップで起動された場合のディープ
  // リンク（2026-09-02追加）。`globalRouter`は`MaterialApp.router`が
  // `goRouterProvider`を読む最初のフレームで埋まるため、その後まで待つ。
  final launchPayload = await consumeLaunchNotificationPayload();
  if (launchPayload != null) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => navigateFromNotificationPayload(launchPayload),
    );
  }
}

class DaiDaiApp extends ConsumerWidget {
  const DaiDaiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accentColor = ref.watch(accentColorProvider);
    final gekigaBackgroundColor = ref.watch(gekigaBackgroundColorProvider);
    final appLocale = ref.watch(appLocaleProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final uiStyle = ref.watch(appUiStyleProvider);
    // 設定タブの「フォントデザイン」（2026-09-06追加、2026-09-07に劇画も
    // 対象化）。
    final fontFamily = ref.watch(fontDesignProvider).fontFamily;
    // 劇画スタイルはライト/ダークどちらのthemeModeでも同じ見た目にするため、
    // theme/darkThemeの両方に同一のThemeDataを渡す（chat_screen.dartの
    // 既存方針をアプリ全体に拡張したもの）。switch式にしているのは、新しい
    // スタイルを追加した際に対応漏れをコンパイラが検知できるようにするため。
    final theme = switch (uiStyle) {
      AppUiStyle.flat => AppTheme.light(accentColor, fontFamily: fontFamily),
      AppUiStyle.gekiga => GekigaTheme.build(
        gekigaBackgroundColor,
        fontFamily: fontFamily,
      ),
      AppUiStyle.glass => GlassTheme.light(accentColor, fontFamily: fontFamily),
    };
    final darkTheme = switch (uiStyle) {
      AppUiStyle.flat => AppTheme.dark(accentColor, fontFamily: fontFamily),
      AppUiStyle.gekiga => GekigaTheme.build(
        gekigaBackgroundColor,
        fontFamily: fontFamily,
      ),
      AppUiStyle.glass => GlassTheme.dark(accentColor, fontFamily: fontFamily),
    };
    return MaterialApp.router(
      title: 'DaiDai',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      locale: appLocale.locale,
      supportedLocales: AppLocale.values.map((l) => l.locale),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        // 共有ノート機能（appflowy_editor、2026-09-06追加）が要求する
        // ローカライズデリゲート。
        AppFlowyEditorLocalizations.delegate,
      ],
      routerConfig: ref.watch(goRouterProvider),
    );
  }
}
