import 'package:cloud_firestore/cloud_firestore.dart';

/// 寄合単位の予定/日程調整の「種類（カテゴリ）」（2026-09-11追加）。
///
/// `CalendarEvent`/`ScheduleCoordination`の両方から共有して参照される
/// （`CalendarEvent.categoryId`/`ScheduleCoordination.categoryId`）。
/// `GroupRole`と違い色分けそのものが目的の機能のため、[color]は必須
/// （色を持たないカテゴリという概念を認めない）。
class CalendarCategory {
  const CalendarCategory({
    required this.categoryId,
    required this.roomId,
    required this.name,
    required this.color,
    this.createdAt,
  });

  final String categoryId;
  final String roomId;
  final String name;

  /// 0xRRGGBB形式（アルファ無し）。
  final int color;

  /// カテゴリ一覧の並び順（作成順）に使う。
  final Timestamp? createdAt;

  factory CalendarCategory.fromJson(
    String categoryId,
    Map<String, dynamic> json,
  ) {
    return CalendarCategory(
      categoryId: categoryId,
      roomId: json['roomId'] as String,
      name: json['name'] as String,
      color: json['color'] as int,
      createdAt: json['createdAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'roomId': roomId,
      'name': name,
      'color': color,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }
}
