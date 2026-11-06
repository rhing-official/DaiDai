import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repository_providers.dart';

/// メッセージ画面の通知カード（予定・日程調整・投票・ノートの作成通知）が指す対象の種類。
enum NoticeTargetKind { calendarEvent, scheduleCoordination, poll, note }

/// 通知カードの対象が今も存在するかを調べる範囲（2026-11-02）。`(種類, 一対か, 会話id, 寄合id)`。
typedef NoticeTargetScope = (NoticeTargetKind, bool, String, String);

/// その寄合に今ある対象のid一覧。通知カードは自分のidがここに無ければ「削除済み」と
/// 表示し、タップしても何も起きなくする。読み込み中・取得失敗では何も出さない（削除済みと
/// 誤って表示しない為、呼び出し側はデータが無い間は存在するものとして扱う）。
final noticeTargetIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, NoticeTargetScope>((ref, scope) {
      final (kind, isDm, conversationId, roomId) = scope;
      switch (kind) {
        case NoticeTargetKind.calendarEvent:
          return ref
              .watch(calendarEventRepositoryProvider)
              .watchEvents(
                isDm: isDm,
                conversationId: conversationId,
                roomId: roomId,
              )
              .map((items) => {for (final e in items) e.eventId});
        case NoticeTargetKind.scheduleCoordination:
          return ref
              .watch(scheduleCoordinationRepositoryProvider)
              .watchCoordinations(
                isDm: isDm,
                conversationId: conversationId,
                roomId: roomId,
              )
              .map((items) => {for (final e in items) e.coordinationId});
        case NoticeTargetKind.poll:
          return ref
              .watch(pollRepositoryProvider)
              .watchPolls(
                isDm: isDm,
                conversationId: conversationId,
                roomId: roomId,
              )
              .map((items) => {for (final e in items) e.pollId});
        case NoticeTargetKind.note:
          return ref
              .watch(noteRepositoryProvider)
              .watchNotes(
                isDm: isDm,
                conversationId: conversationId,
                roomId: roomId,
              )
              .map((items) => {for (final e in items) e.noteId});
      }
    });
