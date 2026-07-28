import 'package:cloud_firestore/cloud_firestore.dart';

/// カスタムロールに持たせられる権限。DaiDaiに実在する管理操作にのみ対応させる
/// （Discordのボイスチャンネル・AutoMod等、DaiDaiに存在しない機能の権限は無い）。
class GroupPermission {
  GroupPermission._();

  /// 寄合の追加・削除。
  static const manageRooms = 'manageRooms';

  /// ロールの作成・編集・削除・メンバーへの付与。
  static const manageRoles = 'manageRoles';

  /// 既読機能のオン/オフ。
  static const manageReadReceipts = 'manageReadReceipts';

  /// 参加リクエストの承認・却下。
  static const manageJoinRequests = 'manageJoinRequests';

  /// 招待リンクの作成。
  static const createInvite = 'createInvite';

  static const all = {
    manageRooms,
    manageRoles,
    manageReadReceipts,
    manageJoinRequests,
    createInvite,
  };
}

/// 広場のカスタムロール。名前・色（呼び名のフォントカラー）に加え、権限
/// （[GroupPermission]の部分集合）を持つ。長（[Group.ownerId]）は常に全権限を
/// 持つ特別な存在としてロールとは別枠で扱う（`memberRoles`の「モデレーター」は
/// 廃止し、この仕組みに統合した、2026-07-28）。
///
/// 広場には必ず1件、削除・メンバーからの除外ができない基準ロール
/// （[isEveryone]、Discordの`@everyone`相当）が存在し、全メンバーに暗黙に
/// 適用される。それ以外のロールは[Group.roleAssignments]で複数付与できる。
class GroupRole {
  const GroupRole({
    required this.roleId,
    required this.groupId,
    required this.name,
    required this.color,
    required this.permissions,
    this.isEveryone = false,
    this.createdAt,
  });

  final String roleId;
  final String groupId;
  final String name;

  /// 0xRRGGBB形式（アルファ無し）。nullなら呼び名の色を上書きしない
  /// （色を持たないロール、または[isEveryone]の既定値）。
  final int? color;

  final Set<String> permissions;

  /// 全メンバーに自動適用される基準ロールかどうか。広場に1件だけ存在する。
  final bool isEveryone;

  /// ロール一覧の並び順（作成順）に使う。
  final Timestamp? createdAt;

  factory GroupRole.fromJson(String roleId, Map<String, dynamic> json) {
    return GroupRole(
      roleId: roleId,
      groupId: json['groupId'] as String,
      name: json['name'] as String,
      color: json['color'] as int?,
      permissions: Set<String>.from(json['permissions'] as List? ?? const []),
      isEveryone: json['isEveryone'] as bool? ?? false,
      createdAt: json['createdAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'name': name,
      'color': color,
      'permissions': permissions.toList(),
      'isEveryone': isEveryone,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }
}
