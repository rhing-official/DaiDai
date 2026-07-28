import 'package:cloud_firestore/cloud_firestore.dart';

/// 広場のカスタムロール（見た目専用）。名前と色を持つだけで、`Group.memberRoles`
/// （長・モデレーター・メンバーという実際の権限区分）とは無関係。メッセージ画面の
/// アイコン横の呼び名のフォントカラーに使う（`Group.roleAssignments`/
/// `Room.roleAssignments`で誰がどのロールかを管理する）。
class GroupRole {
  const GroupRole({
    required this.roleId,
    required this.groupId,
    required this.name,
    required this.color,
    this.createdAt,
  });

  final String roleId;
  final String groupId;
  final String name;

  /// 0xRRGGBB形式（アルファ無し）。
  final int color;

  /// ロール一覧の並び順（作成順）に使う。
  final Timestamp? createdAt;

  factory GroupRole.fromJson(String roleId, Map<String, dynamic> json) {
    return GroupRole(
      roleId: roleId,
      groupId: json['groupId'] as String,
      name: json['name'] as String,
      color: json['color'] as int,
      createdAt: json['createdAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'name': name,
      'color': color,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }
}
