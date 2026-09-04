import 'package:cloud_firestore/cloud_firestore.dart';

/// daidai横丁のペタピタパッケージ（[StickerPack]）内の1枚。DaiDaiアプリでの
/// 送信単位（技術仕様書7.5参照、2026-08-11追加）。
class Sticker {
  const Sticker({
    required this.stickerId,
    required this.name,
    required this.imageUrl,
    this.roles = const [],
  });

  final String stickerId;
  final String name;
  final String imageUrl;

  /// このペタピタが対応する[StickerRole.roleId]のリスト（0件以上、
  /// 2026-09-05追加）。メッセージ内容に応じたペタピタ提案（
  /// `lib/utils/sticker_suggestion.dart`）で、入力文字列がいずれかの役割の
  /// キーワードに一致した際、その役割idを`roles`に含むスタンプが候補になる。
  final List<String> roles;

  factory Sticker.fromJson(Map<String, dynamic> json) {
    return Sticker(
      stickerId: json['stickerId'] as String,
      name: json['name'] as String,
      imageUrl: json['imageUrl'] as String,
      roles: (json['roles'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'stickerId': stickerId,
    'name': name,
    'imageUrl': imageUrl,
    'roles': roles,
  };
}

/// daidai横丁で販売されるペタピタパッケージ（技術仕様書7.5参照、
/// 2026-08-11追加）。複数枚の[Sticker]をまとめた販売単位で、購入すると
/// 中の[Sticker]全てをDaiDaiアプリで送信できるようになる。
class StickerPack {
  const StickerPack({
    required this.packId,
    required this.creatorId,
    required this.name,
    required this.price,
    required this.stickers,
    required this.category,
    required this.tags,
    required this.salesCount,
    this.createdAt,
  });

  final String packId;
  final String creatorId;
  final String name;

  /// 円単位の価格。0円（無料パック）を許容する。
  final int price;

  final List<Sticker> stickers;
  final String category;
  final List<String> tags;
  final int salesCount;
  final Timestamp? createdAt;

  factory StickerPack.fromJson(String packId, Map<String, dynamic> json) {
    return StickerPack(
      packId: packId,
      creatorId: json['creatorId'] as String,
      name: json['name'] as String,
      price: json['price'] as int,
      stickers: (json['stickers'] as List<dynamic>)
          .map((e) => Sticker.fromJson(e as Map<String, dynamic>))
          .toList(),
      category: json['category'] as String,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      salesCount: json['salesCount'] as int? ?? 0,
      createdAt: json['createdAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {
    'creatorId': creatorId,
    'name': name,
    'price': price,
    'stickers': stickers.map((e) => e.toJson()).toList(),
    'category': category,
    'tags': tags,
    'salesCount': salesCount,
    'createdAt': createdAt,
  };
}
