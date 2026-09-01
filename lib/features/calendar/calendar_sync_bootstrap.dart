import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/calendar_event_sync.dart';
import '../../providers/repository_providers.dart';
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

    final claimed = await repo.claimSyncTask(
      isDm: task.isDm,
      conversationId: task.conversationId,
      roomId: task.roomId,
      eventId: task.eventId,
      uid: widget.currentUserId,
      expectedStatus: CalendarSyncStatus.pending,
    );
    if (!claimed) return;

    final accessToken = await _authService.getAccessTokenSilently();
    if (accessToken == null) {
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
          event: event,
        );
      } else {
        try {
          await _syncService.updateGoogleEvent(
            accessToken: accessToken,
            googleEventId: existingGoogleEventId,
            event: event,
          );
          googleEventId = existingGoogleEventId;
        } on GoogleCalendarEventNotFoundException {
          // ユーザーがGoogle Calendar側で直接削除した場合等。作り直す。
          googleEventId = await _syncService.createGoogleEvent(
            accessToken: accessToken,
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
    ref.listen(_pendingSyncTasksProvider(widget.currentUserId), (
      previous,
      next,
    ) {
      final tasks = next.asData?.value;
      if (tasks == null) return;
      for (final task in tasks) {
        _processTask(task);
      }
    });
    return widget.child;
  }
}

final _pendingSyncTasksProvider = StreamProvider.family(
  (ref, String uid) =>
      ref.watch(calendarEventRepositoryProvider).watchPendingSyncTasks(uid),
);
