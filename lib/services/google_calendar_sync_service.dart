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

  static const _baseUrl =
      'https://www.googleapis.com/calendar/v3/calendars/primary/events';

  /// 作成したGoogle Calendar側のイベントIDを返す。
  Future<String> createGoogleEvent({
    required String accessToken,
    required CalendarEvent event,
  }) async {
    final response = await _client
        .post(
          Uri.parse(_baseUrl),
          headers: _headers(accessToken),
          body: jsonEncode(_toGoogleEventBody(event)),
        )
        .timeout(const Duration(seconds: 10));
    _throwIfError(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as String;
  }

  /// [GoogleCalendarEventNotFoundException]を投げた場合、呼び出し側は
  /// `googleEventId`をクリアして[createGoogleEvent]から作り直すこと。
  Future<void> updateGoogleEvent({
    required String accessToken,
    required String googleEventId,
    required CalendarEvent event,
  }) async {
    final response = await _client
        .put(
          Uri.parse('$_baseUrl/$googleEventId'),
          headers: _headers(accessToken),
          body: jsonEncode(_toGoogleEventBody(event)),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 404 || response.statusCode == 410) {
      throw GoogleCalendarEventNotFoundException();
    }
    _throwIfError(response);
  }

  /// 既にGoogle側に存在しない（404/410）場合も、削除としては成功扱いにする
  /// （既に無いなら目的は達成されている）。
  Future<void> deleteGoogleEvent({
    required String accessToken,
    required String googleEventId,
  }) async {
    final response = await _client
        .delete(
          Uri.parse('$_baseUrl/$googleEventId'),
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
