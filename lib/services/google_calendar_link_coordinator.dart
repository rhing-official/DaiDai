import 'google_calendar_auth_service.dart';
import 'google_calendar_sync_service.dart';

/// Googleカレンダー連携のON/OFF操作をまとめる（2026-09-23追加）。
/// [GoogleCalendarAuthService]（スコープ同意・トークン取得）と
/// [GoogleCalendarSyncService]（Calendar APIの実呼び出し）はそれぞれ
/// 単一責務のまま、「同意→専用カレンダー作成」「専用カレンダー削除」という
/// 2ステップの組み合わせだけをここに閉じ込める（`chat_panes.dart`の
/// `_CalendarButton`・`settings_tab.dart`の`_GoogleCalendarSyncRow`という
/// 2つの導線から同じ手順を重複実装しないため）。
class GoogleCalendarLinkCoordinator {
  GoogleCalendarLinkCoordinator({
    GoogleCalendarAuthService? authService,
    GoogleCalendarSyncService? syncService,
  }) : _authService = authService ?? GoogleCalendarAuthService(),
       _syncService = syncService ?? GoogleCalendarSyncService();

  final GoogleCalendarAuthService _authService;
  final GoogleCalendarSyncService _syncService;

  /// 同意画面を出し、承諾されたら専用カレンダー（「DaiDai」）を作成して
  /// そのidを返す。ユーザーがキャンセルした場合はnullを返す（呼び出し側は
  /// `googleCalendarSyncEnabled`を更新せずnullのまま据え置く）。
  /// [GoogleCalendarNotConfiguredException]等はそのまま呼び出し側へ伝播する。
  Future<String?> connect() async {
    final accessToken = await _authService.requestConsent();
    if (accessToken == null) return null;
    return _syncService.createCalendar(accessToken: accessToken);
  }

  /// 専用カレンダーごと削除する（連携解除時）。ベストエフォートの後始末
  /// なので、アクセストークンが取れない・API呼び出しが失敗した場合も
  /// 例外を投げず黙って諦める（連携解除自体＝ローカルのフラグクリアは
  /// この呼び出しの成否に関わらず成立させたいため、呼び出し側で必ず
  /// `await`はするがtry/catchは不要）。
  Future<void> disconnect(String? calendarId) async {
    if (calendarId == null) return;
    try {
      final accessToken = await _authService.getAccessTokenSilently();
      if (accessToken == null) return;
      await _syncService.deleteCalendar(
        accessToken: accessToken,
        calendarId: calendarId,
      );
    } catch (_) {
      // Google側の削除に失敗しても、連携解除フロー自体は継続させる。
    }
  }
}
