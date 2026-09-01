import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/calendar_event.dart';
import '../models/calendar_event_sync.dart';

/// 寄合単位の共有カレンダー機能のRepository（2026-09-01追加）。
///
/// `AlbumRepository`と同じく、DM/広場固有の複雑な概念には依存せず
/// 「isDm＋conversationId（dmId|groupId）＋roomId」だけに正規化した薄い
/// 実装にしている。操作権限は寄合の全メンバーが対等（firestore.rules側も
/// `manageRooms`等の広場権限とは連動させない）。
///
/// Googleカレンダーへの実際のAPI呼び出しはこのRepositoryの責務ではない
/// （`GoogleCalendarSyncService`/`CalendarSyncWorker`に分離）。ここでは
/// Firestore上の予定本体と、各住人の同期状態（`syncStates`）のCRUDのみを扱う。
abstract class CalendarEventRepository {
  Stream<List<CalendarEvent>> watchEvents({
    required bool isDm,
    required String conversationId,
    required String roomId,
  });

  Future<CalendarEvent> createEvent({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String title,
    String? description,
    required DateTime startAt,
    DateTime? endAt,
    required bool isAllDay,
    String? location,
    required String createdBy,
  });

  Future<void> updateEvent({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
    required String updatedBy,
    String? title,
    String? description,
    DateTime? startAt,
    DateTime? endAt,
    bool? isAllDay,
    String? location,
  });

  /// 予定を削除する。参加者全員の`syncStates`を`pendingDelete`にしてから
  /// 本体を削除する2段階の処理を行う（`CalendarSyncWorker`が`pendingDelete`
  /// を見てGoogle側のイベントも削除できるようにするため）。
  Future<void> deleteEvent({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
  });

  /// 自分の同期状態を購読する（イベント詳細画面のインジケータ表示用）。
  Stream<CalendarEventSync?> watchSyncState({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
    required String uid,
  });

  /// 自分の同期状態を書き込む（`CalendarSyncWorker`専用）。
  Future<void> writeSyncState({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
    required CalendarEventSync syncState,
  });

  /// このユーザーの`pending`/`pendingDelete`な同期状態を、寄合を横断して
  /// 監視する（`CalendarSyncWorker`専用、`collectionGroup`クエリを使う）。
  Stream<List<CalendarEventSyncTask>> watchPendingSyncTasks(String uid);

  /// [expectedStatus]（`pending`または`pendingDelete`）から処理中状態
  /// （`syncing`/`deleting`）への遷移を試みる（`CalendarSyncWorker`専用）。
  /// 複数端末が同時にオンラインの場合の二重登録・二重削除を防ぐ楽観ロック。
  /// 既に他端末が処理中/処理済みなら`false`を返す。
  Future<bool> claimSyncTask({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
    required String uid,
    required CalendarSyncStatus expectedStatus,
  });

  /// 一覧表示用の非正規化カウンタ（[CalendarEvent.syncedCount]）を+1する
  /// （`CalendarSyncWorker`専用、同期成功時に呼ぶ）。
  Future<void> incrementSyncedCount({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
  });

  /// 自分の同期状態ドキュメントを削除する（`CalendarSyncWorker`専用）。
  /// `pendingDelete`の処理が完了した後の掃除、または未連携で最初から
  /// 同期する必要がない場合に使う。
  Future<void> deleteSyncState({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
    required String uid,
  });
}

/// [CalendarEventRepository.watchPendingSyncTasks]が返す、1件の未同期タスク
/// （どの寄合の・どの予定の・どんな同期状態か）をまとめたもの。
///
/// [event]は[CalendarSyncStatus.pendingDelete]の場合にnullになりうる。
/// `deleteEvent`は参加者のsyncStatesを`pendingDelete`にしてから予定本体を
/// 削除するため、ワーカーがこのタスクを見つけた時点では既に予定本体が
/// 存在しない（Google側の削除には`syncState.googleEventId`だけあれば足りる
/// ため、これは問題にならない）。
class CalendarEventSyncTask {
  const CalendarEventSyncTask({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.eventId,
    required this.event,
    required this.syncState,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;

  /// [event]がnull（`pendingDelete`で予定本体が既に消えている）の場合でも
  /// 常に有効な値を持つ（`claimSyncTask`等の呼び出しに必要なため）。
  final String eventId;
  final CalendarEvent? event;
  final CalendarEventSync syncState;
}

class FirestoreCalendarEventRepository implements CalendarEventRepository {
  FirestoreCalendarEventRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _roomsCollection(
    bool isDm,
    String conversationId,
  ) {
    final topLevel = isDm ? 'directMessages' : 'groups';
    return _firestore
        .collection(topLevel)
        .doc(conversationId)
        .collection('rooms');
  }

  CollectionReference<Map<String, dynamic>> _eventsCollection({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) {
    return _roomsCollection(
      isDm,
      conversationId,
    ).doc(roomId).collection('calendarEvents');
  }

  DocumentReference<Map<String, dynamic>> _eventRef({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
  }) {
    return _eventsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).doc(eventId);
  }

  CollectionReference<Map<String, dynamic>> _syncStatesCollection({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
  }) {
    return _eventRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      eventId: eventId,
    ).collection('syncStates');
  }

  /// この寄合の参加者一覧（一対は`participants`、広場は`memberIds`）。
  Future<List<String>> _participantIds({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) async {
    final roomDoc = await _roomsCollection(
      isDm,
      conversationId,
    ).doc(roomId).get();
    final data = roomDoc.data();
    if (data == null) return const [];
    final field = isDm ? 'participants' : 'memberIds';
    return (data[field] as List?)?.cast<String>() ?? const [];
  }

  @override
  Stream<List<CalendarEvent>> watchEvents({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) {
    return _eventsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).snapshots().map((snapshot) {
      final events =
          snapshot.docs
              .map((doc) => CalendarEvent.fromJson(doc.id, doc.data()))
              .toList()
            ..sort(
              (a, b) => a.startAt.millisecondsSinceEpoch.compareTo(
                b.startAt.millisecondsSinceEpoch,
              ),
            );
      return events;
    });
  }

  @override
  Future<CalendarEvent> createEvent({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String title,
    String? description,
    required DateTime startAt,
    DateTime? endAt,
    required bool isAllDay,
    String? location,
    required String createdBy,
  }) async {
    final ref = _eventsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).doc();
    final event = CalendarEvent(
      eventId: ref.id,
      roomId: roomId,
      title: title,
      description: description,
      startAt: Timestamp.fromDate(startAt),
      endAt: endAt != null ? Timestamp.fromDate(endAt) : null,
      isAllDay: isAllDay,
      location: location,
      createdBy: createdBy,
    );

    final participantIds = await _participantIds(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    );
    final batch = _firestore.batch();
    batch.set(ref, event.toJson());
    final syncStates = _syncStatesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      eventId: ref.id,
    );
    for (final uid in participantIds) {
      batch.set(
        syncStates.doc(uid),
        CalendarEventSync(
          uid: uid,
          status: CalendarSyncStatus.pending,
        ).toJson(),
      );
    }
    await batch.commit();
    return event;
  }

  @override
  Future<void> updateEvent({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
    required String updatedBy,
    String? title,
    String? description,
    DateTime? startAt,
    DateTime? endAt,
    bool? isAllDay,
    String? location,
  }) async {
    final ref = _eventRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      eventId: eventId,
    );
    final update = <String, dynamic>{
      'updatedBy': updatedBy,
      'updatedAt': FieldValue.serverTimestamp(),
      'syncedCount': 0,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (startAt != null) 'startAt': Timestamp.fromDate(startAt),
      if (endAt != null) 'endAt': Timestamp.fromDate(endAt),
      if (isAllDay != null) 'isAllDay': isAllDay,
      if (location != null) 'location': location,
    };

    final participantIds = await _participantIds(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    );
    final batch = _firestore.batch();
    batch.update(ref, update);
    final syncStates = _syncStatesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      eventId: eventId,
    );
    for (final uid in participantIds) {
      // googleEventIdは保持したままpendingに戻す。CalendarSyncWorkerが
      // googleEventIdの有無で作成/更新を自然に分岐できるようにするため。
      batch.set(syncStates.doc(uid), {
        'uid': uid,
        'status': CalendarSyncStatus.pending.name,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  @override
  Future<void> deleteEvent({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
  }) async {
    final participantIds = await _participantIds(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    );
    final syncStates = _syncStatesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      eventId: eventId,
    );

    // (1) 全参加者のsyncStatesをpendingDeleteにする
    // （CalendarSyncWorkerがGoogle側のイベントを削除できるようにするため、
    // 本体を消す前に必ずこのマーカーを立てる）。
    final markBatch = _firestore.batch();
    for (final uid in participantIds) {
      markBatch.set(syncStates.doc(uid), {
        'uid': uid,
        'status': CalendarSyncStatus.pendingDelete.name,
      }, SetOptions(merge: true));
    }
    await markBatch.commit();

    // (2) 予定本体を削除する。
    await _eventRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      eventId: eventId,
    ).delete();
  }

  @override
  Stream<CalendarEventSync?> watchSyncState({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
    required String uid,
  }) {
    return _syncStatesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      eventId: eventId,
    ).doc(uid).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return CalendarEventSync.fromJson(uid, data);
    });
  }

  @override
  Future<void> writeSyncState({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
    required CalendarEventSync syncState,
  }) {
    return _syncStatesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      eventId: eventId,
    ).doc(syncState.uid).set(syncState.toJson());
  }

  @override
  Stream<List<CalendarEventSyncTask>> watchPendingSyncTasks(String uid) {
    // syncStates/{uid}は本人のuidしか読めない（firestore.rules）ため、
    // ドキュメントIDでの絞り込みではなくフィールド`uid`のwhere句で絞り込む
    // （collectionGroupクエリはドキュメントIDでの直接絞り込みができない）。
    return _firestore
        .collectionGroup('syncStates')
        .where('uid', isEqualTo: uid)
        .where(
          'status',
          whereIn: [
            CalendarSyncStatus.pending.name,
            CalendarSyncStatus.pendingDelete.name,
          ],
        )
        .snapshots()
        .asyncMap((snapshot) async {
          final tasks = <CalendarEventSyncTask>[];
          for (final doc in snapshot.docs) {
            // path: {directMessages|groups}/{conversationId}/rooms/{roomId}/
            //   calendarEvents/{eventId}/syncStates/{uid}
            final segments = doc.reference.path.split('/');
            if (segments.length != 10) continue;
            final isDm = segments[0] == 'directMessages';
            final conversationId = segments[1];
            final roomId = segments[3];
            final eventId = segments[5];

            final syncState = CalendarEventSync.fromJson(uid, doc.data());

            final eventDoc = await _eventRef(
              isDm: isDm,
              conversationId: conversationId,
              roomId: roomId,
              eventId: eventId,
            ).get();
            final eventData = eventDoc.data();
            // pendingDeleteは予定本体が既に削除された後の状態のため、
            // eventDataが無いのは正常（上記ドキュメントコメント参照）。
            // pending側でeventDataが無いのは想定外（本体が無いのに
            // syncStatesだけ残っている不整合）なのでスキップする。
            if (eventData == null &&
                syncState.status != CalendarSyncStatus.pendingDelete) {
              continue;
            }

            tasks.add(
              CalendarEventSyncTask(
                isDm: isDm,
                conversationId: conversationId,
                roomId: roomId,
                eventId: eventId,
                event: eventData != null
                    ? CalendarEvent.fromJson(eventId, eventData)
                    : null,
                syncState: syncState,
              ),
            );
          }
          return tasks;
        });
  }

  @override
  Future<bool> claimSyncTask({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
    required String uid,
    required CalendarSyncStatus expectedStatus,
  }) {
    final ref = _syncStatesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      eventId: eventId,
    ).doc(uid);
    return _firestore.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) return false;
      final current = CalendarSyncStatus.fromName(data['status'] as String?);
      if (current != expectedStatus) return false;
      final nextStatus = expectedStatus == CalendarSyncStatus.pendingDelete
          ? CalendarSyncStatus.deleting
          : CalendarSyncStatus.syncing;
      transaction.update(ref, {'status': nextStatus.name});
      return true;
    });
  }

  @override
  Future<void> incrementSyncedCount({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
  }) {
    return _eventRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      eventId: eventId,
    ).update({'syncedCount': FieldValue.increment(1)});
  }

  @override
  Future<void> deleteSyncState({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String eventId,
    required String uid,
  }) {
    return _syncStatesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      eventId: eventId,
    ).doc(uid).delete();
  }
}
