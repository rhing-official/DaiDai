import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/calendar_event_sync.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_providers.dart';
import '../../repositories/calendar_event_repository.dart';
import '../../services/google_calendar_auth_service.dart';
import '../../services/google_calendar_sync_service.dart';

/// ログイン済みユーザーが判明した時点で、Googleカレンダー同期のバック
/// グラウンド処理を開始する（[PushNotificationBootstrap]と同様、`AppGate`で
/// HomeScreenの上位をラップして使う、2026-09-01追加）。
///
/// サーバー（Cloud Functions）はGoogleのリフレッシュトークンを一切保存
/// しないクライアント主導の同期方式のため、この端末アプリが起動している
/// 間だけ、自分の`pending`/`pendingDelete`な同期状態（[CalendarEventRepository.
/// watchPendingSyncTasks]）を監視してGoogle Calendar APIを呼ぶ。
class CalendarSyncBootstrap extends ConsumerStatefulWidget {
  const CalendarSyncBootstrap({
    required this.currentUserId,
    required this.child,
    super.key,
  });

  final String currentUserId;
  final Widget child;

  @override
  ConsumerState<CalendarSyncBootstrap> createState() =>
      _CalendarSyncBootstrapState();
}

class _CalendarSyncBootstrapState extends ConsumerState<CalendarSyncBootstrap> {
  final _authService = GoogleCalendarAuthService();
  final _syncService = GoogleCalendarSyncService();

  Future<void> _processTask(CalendarEventSyncTask task) async {
    final repo = ref.read(calendarEventRepositoryProvider);
    switch (task.syncState.status) {
      case CalendarSyncStatus.pending:
        await _processPending(repo, task);
      case CalendarSyncStatus.pendingDelete:
        await _processPendingDelete(repo, task);
      case CalendarSyncStatus.syncing:
      case CalendarSyncStatus.synced:
      case CalendarSyncStatus.failed:
      case CalendarSyncStatus.skipped:
      case CalendarSyncStatus.deleting:
        // watchPendingSyncTasksはpending/pendingDeleteのみを返すため
        // 到達しないが、念のため何もしない。
        break;
    }
  }

  Future<void> _processPending(
    CalendarEventRepository repo,
    CalendarEventSyncTask task,
  ) async {
    final event = task.event;
    if (event == null) return;

    // Googleへ同期済みの予定の内容更新だけを処理する（2026-10-04変更）。
    // 同期は出欠で参加を保存した時に`CalendarRsvpSync`が行うため、
    // Google側にまだ無い（googleEventIdが無い）pendingは、旧仕様（予定作成時に
    // 参加者全員分を自動でpendingにしていた）の残骸。参加していない住人の
    // Googleカレンダーに勝手に予定を入れないよう、掃除するだけにする。
    if (task.syncState.googleEventId == null) {
      await repo.deleteSyncState(
        isDm: task.isDm,
        conversationId: task.conversationId,
        roomId: task.roomId,
        eventId: task.eventId,
        uid: widget.currentUserId,
      );
      return;
    }

    final liveUser = ref
        .read(watchedUserProvider(widget.currentUserId))
        .asData
        ?.value;
    // ユーザー情報が未取得の間は判断できないため何もしない（pendingのまま
    // 残り、取得後の再購読で処理される）。
    if (liveUser == null) return;

    final accessToken = liveUser.googleCalendarSyncEnabled == true
        ? await _authService.getAccessTokenSilently()
        : null;
    final calendarId = liveUser.googleCalendarId;
    if (liveUser.googleCalendarSyncEnabled == true &&
        (accessToken == null || calendarId == null)) {
      // 連携済みだがアクセストークンが取れない（Webではリロード後・失効後は
      // ユーザー操作なしに取得できない）。skippedにして捨てず、pendingのまま
      // 残す。カレンダー画面の「再接続して同期」でトークンを取り直すと処理
      // される（2026-10-04変更、以前はここでskippedにして二度と同期されなかった）。
      debugPrint(
        'CalendarSync: pending保持 token=${accessToken != null} calendarId=$calendarId',
      );
      return;
    }

    final claimed = await repo.claimSyncTask(
      isDm: task.isDm,
      conversationId: task.conversationId,
      roomId: task.roomId,
      eventId: task.eventId,
      uid: widget.currentUserId,
      expectedStatus: CalendarSyncStatus.pending,
    );
    if (!claimed) return;

    if (accessToken == null || calendarId == null) {
      // 連携していない（オプトインしていない）住人。
      await repo.writeSyncState(
        isDm: task.isDm,
        conversationId: task.conversationId,
        roomId: task.roomId,
        eventId: task.eventId,
        syncState: CalendarEventSync(
          uid: widget.currentUserId,
          status: CalendarSyncStatus.skipped,
        ),
      );
      return;
    }

    try {
      final existingGoogleEventId = task.syncState.googleEventId;
      String googleEventId;
      if (existingGoogleEventId == null) {
        googleEventId = await _syncService.createGoogleEvent(
          accessToken: accessToken,
          calendarId: calendarId,
          event: event,
        );
      } else {
        try {
          await _syncService.updateGoogleEvent(
            accessToken: accessToken,
            calendarId: calendarId,
            googleEventId: existingGoogleEventId,
            event: event,
          );
          googleEventId = existingGoogleEventId;
        } on GoogleCalendarEventNotFoundException {
          // ユーザーがGoogle Calendar側で直接削除した場合、または連携解除→
          // 再連携で専用カレンダーが作り直された場合等。作り直す。
          googleEventId = await _syncService.createGoogleEvent(
            accessToken: accessToken,
            calendarId: calendarId,
            event: event,
          );
        }
      }

      await repo.writeSyncState(
        isDm: task.isDm,
        conversationId: task.conversationId,
        roomId: task.roomId,
        eventId: task.eventId,
        syncState: CalendarEventSync(
          uid: widget.currentUserId,
          googleEventId: googleEventId,
          googleCalendarId: calendarId,
          status: CalendarSyncStatus.synced,
          syncedAt: Timestamp.now(),
        ),
      );
      await repo.incrementSyncedCount(
        isDm: task.isDm,
        conversationId: task.conversationId,
        roomId: task.roomId,
        eventId: task.eventId,
      );
    } catch (e) {
      debugPrint('CalendarSync: 同期失敗 $e');
      await repo.writeSyncState(
        isDm: task.isDm,
        conversationId: task.conversationId,
        roomId: task.roomId,
        eventId: task.eventId,
        syncState: CalendarEventSync(
          uid: widget.currentUserId,
          googleEventId: task.syncState.googleEventId,
          status: CalendarSyncStatus.failed,
          lastError: e.toString(),
        ),
      );
    }
  }

  Future<void> _processPendingDelete(
    CalendarEventRepository repo,
    CalendarEventSyncTask task,
  ) async {
    final claimed = await repo.claimSyncTask(
      isDm: task.isDm,
      conversationId: task.conversationId,
      roomId: task.roomId,
      eventId: task.eventId,
      uid: widget.currentUserId,
      expectedStatus: CalendarSyncStatus.pendingDelete,
    );
    if (!claimed) return;

    final googleEventId = task.syncState.googleEventId;
    if (googleEventId == null) {
      // 一度もGoogle側に反映していなかった（未連携・作成前に削除された等）
      // ため、消すものが無い。掃除するだけでよい。
      await repo.deleteSyncState(
        isDm: task.isDm,
        conversationId: task.conversationId,
        roomId: task.roomId,
        eventId: task.eventId,
        uid: widget.currentUserId,
      );
      return;
    }

    final accessToken = await _authService.getAccessTokenSilently();
    if (accessToken == null) {
      // 未連携（連携を後から解除した等）。Google側に既に存在するかは
      // 確認しようがないため、このsyncStatesだけ掃除して諦める。
      await repo.deleteSyncState(
        isDm: task.isDm,
        conversationId: task.conversationId,
        roomId: task.roomId,
        eventId: task.eventId,
        uid: widget.currentUserId,
      );
      return;
    }

    try {
      await _syncService.deleteGoogleEvent(
        accessToken: accessToken,
        calendarId: task.syncState.googleCalendarId,
        googleEventId: googleEventId,
      );
      await repo.deleteSyncState(
        isDm: task.isDm,
        conversationId: task.conversationId,
        roomId: task.roomId,
        eventId: task.eventId,
        uid: widget.currentUserId,
      );
    } catch (e) {
      // 失敗した場合はpendingDeleteに戻し、次回のワーカー起動時に再試行する。
      await repo.writeSyncState(
        isDm: task.isDm,
        conversationId: task.conversationId,
        roomId: task.roomId,
        eventId: task.eventId,
        syncState: CalendarEventSync(
          uid: widget.currentUserId,
          googleEventId: googleEventId,
          status: CalendarSyncStatus.pendingDelete,
          lastError: e.toString(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pendingSyncTasksProvider(widget.currentUserId), (
      previous,
      next,
    ) {
      if (next.hasError) {
        // 購読の失敗（複合インデックス未デプロイ・権限エラー等）が無言で
        // 同期を止めないよう、ログに残す（2026-10-04追加）。
        debugPrint('CalendarSync: 保留タスクの購読に失敗 ${next.error}');
      }
      final tasks = next.asData?.value;
      if (tasks == null) return;
      for (final task in tasks) {
        _processTask(task);
      }
    });
    return widget.child;
  }
}

/// 自分の未処理（pending/pendingDelete）な同期タスク。カレンダー画面の
/// 「再接続して同期」バナーの表示判定にも使う。
final pendingSyncTasksProvider = StreamProvider.family(
  (ref, String uid) =>
      ref.watch(calendarEventRepositoryProvider).watchPendingSyncTasks(uid),
);
