import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/calendar_category.dart';

/// 寄合単位の予定/日程調整の「種類（カテゴリ）」機能のRepository
/// （2026-09-11追加）。`CalendarEventRepository`と同じ「isDm＋
/// conversationId（dmId|groupId）＋roomId」正規化パターンを踏襲する。
///
/// 操作権限は寄合の全メンバーが対等（`CalendarEventRepository`と同じ方針、
/// firestore.rules側も`GroupPermission`のような権限とは連動させない）。
abstract class CalendarCategoryRepository {
  Stream<List<CalendarCategory>> watchCategories({
    required bool isDm,
    required String conversationId,
    required String roomId,
  });

  Future<CalendarCategory> createCategory({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String name,
    required int color,
  });

  Future<void> updateCategory({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String categoryId,
    required String name,
    required int color,
  });

  Future<void> deleteCategory({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String categoryId,
  });
}

class FirestoreCalendarCategoryRepository
    implements CalendarCategoryRepository {
  FirestoreCalendarCategoryRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _categoriesCollection({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) {
    final topLevel = isDm ? 'directMessages' : 'groups';
    return _firestore
        .collection(topLevel)
        .doc(conversationId)
        .collection('rooms')
        .doc(roomId)
        .collection('calendarCategories');
  }

  @override
  Stream<List<CalendarCategory>> watchCategories({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) {
    return _categoriesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).snapshots().map((snapshot) {
      final categories =
          snapshot.docs
              .map((doc) => CalendarCategory.fromJson(doc.id, doc.data()))
              .toList()
            ..sort((a, b) {
              final aMillis = a.createdAt?.millisecondsSinceEpoch ?? 0;
              final bMillis = b.createdAt?.millisecondsSinceEpoch ?? 0;
              return aMillis.compareTo(bMillis);
            });
      return categories;
    });
  }

  @override
  Future<CalendarCategory> createCategory({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String name,
    required int color,
  }) async {
    final ref = _categoriesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).doc();
    final category = CalendarCategory(
      categoryId: ref.id,
      roomId: roomId,
      name: name,
      color: color,
    );
    await ref.set(category.toJson());
    return category;
  }

  @override
  Future<void> updateCategory({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String categoryId,
    required String name,
    required int color,
  }) {
    return _categoriesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).doc(categoryId).update({'name': name, 'color': color});
  }

  @override
  Future<void> deleteCategory({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String categoryId,
  }) {
    return _categoriesCollection(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
    ).doc(categoryId).delete();
  }
}
