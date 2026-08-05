import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import '../l10n/terminology_style.dart';
import '../models/app_ui_style.dart';
import '../models/app_user_preferences.dart';
import '../models/chat_layout_style.dart';
import '../models/message_time_format.dart';
import '../models/send_key_mode.dart';
import 'accent_color_provider.dart';
import 'app_locale_provider.dart';
import 'app_ui_style_provider.dart';
import 'chat_layout_style_provider.dart';
import 'gekiga_background_color_provider.dart';
import 'message_time_format_provider.dart';
import 'send_key_mode_provider.dart';
import 'terminology_style_provider.dart';
import 'theme_mode_provider.dart';

/// ログイン直後、Firestoreに保存されている表示設定（[AppUserPreferences]）で
/// 端末側の状態を上書きする（`AuthGate`から呼ぶ）。値が保存されていない項目
/// （他のどの端末でもまだ一度も変更されていない設定）は端末側の現在値
/// （SharedPreferences由来）をそのまま維持し、Firestoreへの書き戻しは行わない
/// （ユーザーが明示的に変更した時点で初めて同期対象になる）。
void applyRemoteUserPreferences(WidgetRef ref, AppUserPreferences preferences) {
  if (preferences.accentColorArgb != null) {
    ref
        .read(accentColorProvider.notifier)
        .syncFromRemote(Color(preferences.accentColorArgb!));
  }
  if (preferences.gekigaBackgroundColorArgb != null) {
    ref
        .read(gekigaBackgroundColorProvider.notifier)
        .syncFromRemote(Color(preferences.gekigaBackgroundColorArgb!));
  }
  if (preferences.themeMode != null) {
    final mode = ThemeMode.values.firstWhereOrNull(
      (m) => m.name == preferences.themeMode,
    );
    if (mode != null) {
      ref.read(appThemeModeProvider.notifier).syncFromRemote(mode);
    }
  }
  if (preferences.localeCode != null) {
    ref
        .read(appLocaleProvider.notifier)
        .syncFromRemote(AppLocale.fromLanguageCode(preferences.localeCode));
  }
  if (preferences.terminologyStyle != null) {
    ref
        .read(terminologyStyleProvider.notifier)
        .syncFromRemote(
          TerminologyStyle.fromName(preferences.terminologyStyle),
        );
  }
  if (preferences.sendKeyMode != null) {
    ref
        .read(sendKeyModeProvider.notifier)
        .syncFromRemote(SendKeyMode.fromName(preferences.sendKeyMode));
  }
  if (preferences.chatLayoutStyle != null) {
    ref
        .read(chatLayoutStyleProvider.notifier)
        .syncFromRemote(ChatLayoutStyle.fromName(preferences.chatLayoutStyle));
  }
  if (preferences.messageTimeFormat != null) {
    ref
        .read(messageTimeFormatProvider.notifier)
        .syncFromRemote(
          MessageTimeFormat.fromName(preferences.messageTimeFormat),
        );
  }
  if (preferences.appUiStyle != null) {
    ref
        .read(appUiStyleProvider.notifier)
        .syncFromRemote(AppUiStyle.fromName(preferences.appUiStyle));
  }
}
