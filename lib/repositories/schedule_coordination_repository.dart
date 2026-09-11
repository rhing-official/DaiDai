import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/schedule_coordination.dart';
import '../models/schedule_coordination_response.dart';

/// 日程調整機能のRepository（2026-09-05追加）。`CalendarEventRepository`と
/// 同じく「isDm＋conversationId（dmId|groupId）＋roomId」だけに正規化した
/// 薄い実装。Googleカレンダー同期の概念はここには無い。
abstract class ScheduleCoordinationRepository {
  Stream<List<ScheduleCoordination>> watchCoordinations({
    required bool isDm,
    required String conversationId,
    required String roomId,
  });

  Future<ScheduleCoordination> createCoordination({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String title,
    String? description,
    required List<DateTime> candidateDates,
    required String createdBy,
    DateTime? deadline,
    String? categoryId,
  });

  /// 単発で1件だけ取得する（存在しなければnull）。メッセージ画面の日程調整
  /// 開始通知メッセージをタップした際、そのcoordinationIdから取得して
  /// 投票ダイアログを開くために使う。
  Future<ScheduleCoordination?> getCoordination({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
  });

  /// 日程調整を削除する（作成者のみ、firestore.rules参照）。
  Future<void> deleteCoordination({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
  });

  /// この寄合の参加者一覧（一対は`participants`、広場は`memberIds`）。
  Future<List<String>> participantIds({
    required bool isDm,
    required String conversationId,
    required String roomId,
  });

  /// この日程調整への回答一覧を購読する（集計表示・「未回答」の算出用）。
  Stream<List<ScheduleCoordinationResponse>> watchResponses({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
  });

  /// 自分の回答を書き込む（毎回全体を上書き）。
  Future<void> setResponse({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
    required String userId,
    required Map<String, ScheduleCoordinationVote> votes,
  });

  /// 候補の1つを確定する（作成者のみ、一度きり、firestore.rules参照）。
  /// 呼び出し側が別途`CalendarEventRepository.createEvent`で実際の予定を
  /// 作成した後に呼ぶ想定で、このRepository自体は`CalendarEventRepository`
  /// に依存しない（結合を避けるため）。
  Future<void> finalize({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
    required int finalizedCandidateIndex,
    required String finalizedEventId,
  });

  /// この日程調整を`ChatTaskBanner`から自分だけ非表示にする（2026-09-10
  /// 追加）。本体は削除せず、カレンダー画面には引き続き表示される
  /// （[ScheduleCoordination.bannerHiddenFor]参照）。
  Future<void> hideFromBanner({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
    required String userId,
  });
}

class FirestoreScheduleCoordinationRepository
    implements ScheduleCoordinationRepository {
  FirestoreScheduleCoordinationRepository({FirebaseFirestore? firestore})
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

  CollectionReference<Map<String, dynamic>> _coordinationsCollection({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) {
    return _roomsCollection(
      isDm,
      conversationId,
    ).doc(roomId).collection('scheduleCoordinations');
  }

  DocumentReference<Map<String, dynamic>> _coordinationRef({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
  }) {
    return _coordinationsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).doc(coordinationId);
  }

  CollectionReference<Map<String, dynamic>> _responsesCollection({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
  }) {
    return _coordinationRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      coordinationId: coordinationId,
    ).collection('responses');
  }

  @override
  Future<List<String>> participantIds({
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
  Stream<List<ScheduleCoordination>> watchCoordinations({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) {
    return _coordinationsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => ScheduleCoordination.fromJson(doc.id, doc.data()))
          .toList();
    });
  }

  @override
  Future<ScheduleCoordination?> getCoordination({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
  }) async {
    final doc = await _coordinationRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      coordinationId: coordinationId,
    ).get();
    final data = doc.data();
    if (data == null) return null;
    return ScheduleCoordination.fromJson(doc.id, data);
  }

  @override
  Future<ScheduleCoordination> createCoordination({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String title,
    String? description,
    required List<DateTime> candidateDates,
    required String createdBy,
    DateTime? deadline,
    String? categoryId,
  }) async {
    final ref = _coordinationsCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).doc();
    final coordination = ScheduleCoordination(
      coordinationId: ref.id,
      roomId: roomId,
      title: title,
      description: description,
      candidateDates: candidateDates
          .map((d) => Timestamp.fromDate(DateTime(d.year, d.month, d.day)))
          .toList(),
      createdBy: createdBy,
      deadline: deadline != null ? Timestamp.fromDate(deadline) : null,
      categoryId: categoryId,
    );
    await ref.set(coordination.toJson());
    return coordination;
  }

  @override
  Future<void> deleteCoordination({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
  }) {
    return _coordinationRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      coordinationId: coordinationId,
    ).delete();
  }

  @override
  Stream<List<ScheduleCoordinationResponse>> watchResponses({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
  }) {
    return _responsesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      coordinationId: coordinationId,
    ).snapshots().map((snapshot) {
      return snapshot.docs
          .map(
            (doc) => ScheduleCoordinationResponse.fromJson(doc.id, doc.data()),
          )
          .toList();
    });
  }

  @override
  Future<void> setResponse({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
    required String userId,
    required Map<String, ScheduleCoordinationVote> votes,
  }) async {
    final responseRef = _responsesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      coordinationId: coordinationId,
    ).doc(userId);
    final coordinationRef = _coordinationRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      coordinationId: coordinationId,
    );
    // 回答者数の非正規化カウンタ（ScheduleCoordination.responseCount）は、
    // 本人の回答が新規作成される時だけ+1する（CalendarEventRepository.setRsvp
    // と同じ設計）。
    final existing = await responseRef.get();
    await responseRef.set(
      ScheduleCoordinationResponse(userId: userId, votes: votes).toJson(),
    );
    if (!existing.exists) {
      try {
        await coordinationRef.update({
          'responseCount': FieldValue.increment(1),
        });
      } catch (e) {
        // responseCountは非正規化された副次データであり、更新に失敗しても
        // 本来の回答の保存（上記set）自体は既に完了しているため再スローしない
        // （CalendarEventRepository.setRsvpと同じ理由）。
        debugPrint(
          '[scheduleCoordinationRepository.setResponse] responseCount update failed: $e',
        );
      }
    }
  }

  @override
  Future<void> finalize({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
    required int finalizedCandidateIndex,
    required String finalizedEventId,
  }) {
    // finalizeは非正規化カウンタの更新ではなく、この日程調整の主目的である
    // 「確定」そのものの書き込みのため、setResponseのresponseCount更新とは
    // 異なり失敗を握りつぶさず再スローする（呼び出し元がリトライできるよう
    // にするため、schedule_coordination_detail_dialog.dart参照）。
    return _coordinationRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      coordinationId: coordinationId,
    ).update({
      'finalizedCandidateIndex': finalizedCandidateIndex,
      'finalizedEventId': finalizedEventId,
    });
  }

  @override
  Future<void> hideFromBanner({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String coordinationId,
    required String userId,
  }) {
    return _coordinationRef(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      coordinationId: coordinationId,
    ).update({
      'bannerHiddenFor': FieldValue.arrayUnion([userId]),
    });
  }
}
