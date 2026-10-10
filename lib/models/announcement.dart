import 'package:cloud_firestore/cloud_firestore.dart';

/// お便り（運営から全住人への配信）1件（`announcements/{id}`、2026-10-10追加）。
/// 以前は固定UID`official-tayori`の住人から各住人との一対へメッセージとして
/// 配信していたが、住人を持たない「そこにある物」として1件のドキュメントに
/// 変えた。書き込みはCloud Functions（`broadcastAnnouncement`）のみ。
class Announcement {
  const Announcement({required this.id, required this.content, this.createdAt});

  final String id;
  final String content;
  final Timestamp? createdAt;

  factory Announcement.fromJson(String id, Map<String, dynamic> json) {
    return Announcement(
      id: id,
      content: json['content'] as String? ?? '',
      createdAt: json['createdAt'] as Timestamp?,
    );
  }
}
