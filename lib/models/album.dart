import 'package:cloud_firestore/cloud_firestore.dart';

/// 寄合単位の共有アルバム（`directMessages/{dmId}/rooms/{roomId}/albums/{albumId}`
/// または`groups/{groupId}/rooms/{roomId}/albums/{albumId}`、2026-08-30追加）。
///
/// 個人のフォトライブラリではなく、その寄合のメンバー全員が共有する
/// アルバムで、寄合内で送信された画像・動画メッセージを整理して保存する
/// ために使う。登録された画像・動画は寄合の通常のメッセージ削除・保存
/// 期間ルールとは独立して保存される（[AlbumItem]参照）。
class Album {
  const Album({
    required this.albumId,
    required this.roomId,
    required this.name,
    required this.createdBy,
    this.createdAt,
    this.itemCount = 0,
    this.coverItemId,
    this.coverThumbnailUrl,
    this.coverContentType,
  });

  final String albumId;
  final String roomId;
  final String name;
  final String createdBy;
  final Timestamp? createdAt;

  /// 一覧表示用の非正規化カウンタ。アイテム追加・削除のたびに
  /// `AlbumRepository`がバッチ更新する。
  final int itemCount;

  /// 一覧表示用の非正規化キャッシュ（最新のアイテムをカバーに使う）。
  final String? coverItemId;
  final String? coverThumbnailUrl;

  /// image|video。カバーが動画の場合の再生アイコン表示分岐に使う。
  final String? coverContentType;

  factory Album.fromJson(String albumId, Map<String, dynamic> json) {
    return Album(
      albumId: albumId,
      roomId: json['roomId'] as String,
      name: json['name'] as String,
      createdBy: json['createdBy'] as String,
      createdAt: json['createdAt'] as Timestamp?,
      itemCount: json['itemCount'] as int? ?? 0,
      coverItemId: json['coverItemId'] as String?,
      coverThumbnailUrl: json['coverThumbnailUrl'] as String?,
      coverContentType: json['coverContentType'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'roomId': roomId,
    'name': name,
    'createdBy': createdBy,
    'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    'itemCount': itemCount,
    'coverItemId': coverItemId,
    'coverThumbnailUrl': coverThumbnailUrl,
    'coverContentType': coverContentType,
  };

  Album copyWith({
    String? name,
    int? itemCount,
    String? coverItemId,
    String? coverThumbnailUrl,
    String? coverContentType,
  }) {
    return Album(
      albumId: albumId,
      roomId: roomId,
      name: name ?? this.name,
      createdBy: createdBy,
      createdAt: createdAt,
      itemCount: itemCount ?? this.itemCount,
      coverItemId: coverItemId ?? this.coverItemId,
      coverThumbnailUrl: coverThumbnailUrl ?? this.coverThumbnailUrl,
      coverContentType: coverContentType ?? this.coverContentType,
    );
  }
}
