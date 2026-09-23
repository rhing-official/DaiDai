import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/calendar_event.dart';
import '../utils/calendar_time.dart';

/// [event]に対応するGoogle側のイベントが見つからなかった（404/410）ことを表す。
/// ユーザーがGoogle Calendar側で直接削除した場合等に発生し、呼び出し側
/// （`CalendarSyncWorker`）は`googleEventId`をクリアして作り直す。
class GoogleCalendarEventNotFoundException implements Exception {}

/// Googleカレンダーへの実際のAPI呼び出しを担う（2026-09-01追加）。
/// アクセストークンの取得（`GoogleCalendarAuthService`）・Firestore上の
/// 同期状態管理（`CalendarEventRepository`）とは責務を分離している。
/// `googleapis`パッケージは依存追加を避けるため使わず、`http`パッケージで
/// Calendar API v3のRESTを直叩きする（`LinkPreviewRepository`と同じ方針）。
class GoogleCalendarSyncService {
  GoogleCalendarSyncService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const _calendarsBaseUrl =
      'https://www.googleapis.com/calendar/v3/calendars';

  String _eventsBaseUrl(String calendarId) =>
      '$_calendarsBaseUrl/$calendarId/events';

  /// 住人ごとの専用Googleカレンダーを作成し、そのidを返す（2026-09-23追加）。
  /// `calendar.app.created`スコープではこのアプリが作成したカレンダーにしか
  /// 触れられないため、同期を有効にした最初のタイミングで必ず1回呼ぶ
  /// （呼び出し側は返り値を`AppUser.googleCalendarId`として保存する）。
  Future<String> createCalendar({
    required String accessToken,
    String summary = 'DaiDai',
  }) async {
    final response = await _client
        .post(
          Uri.parse(_calendarsBaseUrl),
          headers: _headers(accessToken),
          body: jsonEncode({'summary': summary}),
        )
        .timeout(const Duration(seconds: 10));
    _throwIfError(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as String;
  }

  /// 専用カレンダーごと削除する（連携解除時、2026-09-23追加）。カレンダーに
  /// 含まれる予定もGoogle側でまとめて削除される。既に存在しない場合
  /// （404/410）も成功扱いにする（既に無いなら目的は達成されている）。
  Future<void> deleteCalendar({
    required String accessToken,
    required String calendarId,
  }) async {
    final response = await _client
        .delete(
          Uri.parse('$_calendarsBaseUrl/$calendarId'),
          headers: _headers(accessToken),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 404 || response.statusCode == 410) return;
    _throwIfError(response);
  }

  /// 作成したGoogle Calendar側のイベントIDを返す。[calendarId]は
  /// [createCalendar]で作成した専用カレンダーのid（2026-09-23変更、以前は
  /// `primary`固定だった）。
  Future<String> createGoogleEvent({
    required String accessToken,
    required String calendarId,
    required CalendarEvent event,
  }) async {
    final response = await _client
        .post(
          Uri.parse(_eventsBaseUrl(calendarId)),
          headers: _headers(accessToken),
          body: jsonEncode(_toGoogleEventBody(event)),
        )
        .timeout(const Duration(seconds: 10));
    _throwIfError(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as String;
  }

  /// [GoogleCalendarEventNotFoundException]を投げた場合、呼び出し側は
  /// `googleEventId`をクリアして[createGoogleEvent]から作り直すこと
  /// （専用カレンダーが再作成され[calendarId]が変わった場合も、この
  /// フォールバックで自然に追従する）。
  Future<void> updateGoogleEvent({
    required String accessToken,
    required String calendarId,
    required String googleEventId,
    required CalendarEvent event,
  }) async {
    final response = await _client
        .put(
          Uri.parse('${_eventsBaseUrl(calendarId)}/$googleEventId'),
          headers: _headers(accessToken),
          body: jsonEncode(_toGoogleEventBody(event)),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 404 || response.statusCode == 410) {
      throw GoogleCalendarEventNotFoundException();
    }
    _throwIfError(response);
  }

  /// 既にGoogle側に存在しない（404/410、カレンダー自体が無い場合を含む）
  /// 場合も、削除としては成功扱いにする（既に無いなら目的は達成されている）。
  Future<void> deleteGoogleEvent({
    required String accessToken,
    required String calendarId,
    required String googleEventId,
  }) async {
    final response = await _client
        .delete(
          Uri.parse('${_eventsBaseUrl(calendarId)}/$googleEventId'),
          headers: _headers(accessToken),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 404 || response.statusCode == 410) return;
    _throwIfError(response);
  }

  Map<String, String> _headers(String accessToken) => {
    'Authorization': 'Bearer $accessToken',
    'Content-Type': 'application/json',
  };

  void _throwIfError(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Google Calendar API error ${response.statusCode}: ${response.body}',
      );
    }
  }

  Map<String, dynamic> _toGoogleEventBody(CalendarEvent event) {
    final startLocal = event.startAt.toDate().toLocal();
    final endLocal = event.endAt?.toDate().toLocal();

    return {
      'summary': event.title,
      if (event.description != null) 'description': event.description,
      if (event.location != null) 'location': event.location,
      'start': event.isAllDay
          ? {'date': toDateOnly(startLocal)}
          : {'dateTime': toRfc3339WithOffset(startLocal)},
      'end': event.isAllDay
          ? {'date': toDateOnly(exclusiveAllDayEnd(startLocal, endLocal))}
          : {
              'dateTime': toRfc3339WithOffset(
                endLocal ?? startLocal.add(const Duration(hours: 1)),
              ),
            },
    };
  }
}
