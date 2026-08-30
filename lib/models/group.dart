import 'package:cloud_firestore/cloud_firestore.dart';

import 'group_profile_card.dart';

/// 広場（Group） - 3人以上のグループチャット
class Group {
  const Group({
    required this.groupId,
    required this.name,
    required this.ownerId,
    required this.memberIds,
    required this.memberRoles,
    required this.defaultRoomId,
    this.profileCard,
    this.createdAt,
    this.readReceiptsEnabled = true,
    this.roleAssignments = const {},
    this.rolePriority = const [],
    this.memberPermissions = const {},
    this.roomsEnabled = true,
  });

  final String groupId;
  final String name;

  /// 長（オーナー）のuserId。常に全権限を持つ特別な存在で、カスタムロールの
  /// 付与・削除とは独立している。作成者が初期値だが、`GroupRepository.
  /// transferOwnership`で後から他のメンバーへ譲渡できる（2026-07-28追加）。
  final String ownerId;
  final List<String> memberIds;

  /// userId -> role (owner | member)。「モデレーター」は廃止し
  /// カスタムロール（[roleAssignments]）に統合した（2026-07-28）。
  /// メンバー一覧の表示・退会時のクリーンアップ以外の権限判定には使わない
  /// （権限判定は[ownerId]と[memberPermissions]を使う）。
  final Map<String, String> memberRoles;
  final String defaultRoomId;

  /// userId -> [GroupRole.roleId]のリスト（広場全体でのカスタムロール付与、
  /// 複数可）。全メンバーに暗黙適用される基準ロール（`isEveryone`）は
  /// ここには含めない。
  final Map<String, List<String>> roleAssignments;

  /// カスタムロールの優先順位（呼び名の色を決める順序、先頭が最優先）。
  /// 基準ロール（`isEveryone`）は含めない＝常に最下位。寄合ごとに
  /// `Room.rolePriorityOverride`で上書きできる。
  final List<String> rolePriority;

  /// userId -> 有効な権限文字列のリスト（[GroupPermission]、基準ロール込みで
  /// 解決済み）。firestore.rulesがロールドキュメントを跨いで動的に権限を
  /// 判定できないため、`GroupRepository`がロール・付与の変更のたびに
  /// 再計算してここに非正規化して持たせる（`Room.memberIds`と同じ設計）。
  final Map<String, List<String>> memberPermissions;

  /// 既読機能のオン/オフ（広場全体・長のみ変更可）。オフにすると
  /// `defaultRoomId`の全メッセージ・全メンバー分の既読履歴をサーバーから
  /// 削除する（`GroupRepository.setReadReceiptsEnabled`参照）。
  final bool readReceiptsEnabled;

  /// 広場を代表するプロフィールカード（最大1枚）。未作成ならnull。
  /// メンバー全員が編集できる（`_ProfileTabState`の個人カードとは異なり
  /// 所有者・モデレーター限定ではない）。
  final GroupProfileCard? profileCard;

  final Timestamp? createdAt;

  /// 複数の寄合（テキストチャンネル）を扱うか。falseの場合はサイドバーの
  /// 寄合一覧を出さず、`defaultRoomId`の1つだけを使う単一モード
  /// （2026-07-29追加）。作成時にどちらか選び、後からハンバーガーメニューの
  /// 「寄合を複数扱う」でtrueへの切り替えのみ可能（falseへは戻せない）。
  /// 既存データ（この機能追加前に作られた広場）は全てtrue扱いにする
  /// （fromJsonのデフォルト値、既存の複数寄合表示を維持するため）。
  final bool roomsEnabled;

  factory Group.fromJson(String groupId, Map<String, dynamic> json) {
    final profileCardJson = json['profileCard'] as Map<String, dynamic>?;
    return Group(
      groupId: groupId,
      name: json['name'] as String,
      ownerId: json['ownerId'] as String,
      memberIds: List<String>.from(json['memberIds'] as List),
      memberRoles: Map<String, String>.from(json['memberRoles'] as Map),
      defaultRoomId: json['defaultRoomId'] as String,
      profileCard: profileCardJson != null
          ? GroupProfileCard.fromJson(profileCardJson)
          : null,
      createdAt: json['createdAt'] as Timestamp?,
      readReceiptsEnabled: json['readReceiptsEnabled'] as bool? ?? true,
      roleAssignments: _decodeRoleAssignments(json['roleAssignments']),
      rolePriority: List<String>.from(
        json['rolePriority'] as List? ?? const [],
      ),
      memberPermissions: (json['memberPermissions'] as Map? ?? const {}).map(
        (key, value) =>
            MapEntry(key as String, List<String>.from(value as List)),
      ),
      roomsEnabled: json['roomsEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'ownerId': ownerId,
      'memberIds': memberIds,
      'memberRoles': memberRoles,
      'defaultRoomId': defaultRoomId,
      'profileCard': profileCard?.toJson(),
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'readReceiptsEnabled': readReceiptsEnabled,
      'roleAssignments': roleAssignments,
      'rolePriority': rolePriority,
      'memberPermissions': memberPermissions,
      'roomsEnabled': roomsEnabled,
    };
  }
}

/// [Group.roleAssignments]のfromJson用。旧形式（`Map<String, String>`＝
/// 1人1ロールだった頃のデータ）が万一残っていても空扱いにする
/// （本番はまだテストデータのみのため、フィールドごと作り直す方針）。
Map<String, List<String>> _decodeRoleAssignments(Object? json) {
  if (json is! Map) return const {};
  final result = <String, List<String>>{};
  for (final entry in json.entries) {
    final value = entry.value;
    if (value is List) {
      result[entry.key as String] = List<String>.from(value);
    }
  }
  return result;
}

/// お部屋（Room） - 広場内の実際に会話する場所。
/// フェーズ1では節（カテゴリ）機能は使わず、広場作成時に1つだけ自動生成する。
class Room {
  const Room({
    required this.roomId,
    required this.groupId,
    required this.name,
    required this.memberIds,
    this.lastMessageAt,
    this.createdAt,
    this.roomDeletionRequestedBy,
    this.rolePriorityOverride,
    this.customSettingsEnabled = false,
    this.readReceiptsEnabledOverride,
    this.pinnedMessageIds = const [],
  });

  final String roomId;
  final String groupId;
  final String name;

  /// 広場のmemberIdsを非正規化して保持（セキュリティルールでの参照を単純化するため）。
  final List<String> memberIds;
  final Timestamp? lastMessageAt;

  /// この寄合限定でのロール優先順位の上書き。[customSettingsEnabled]が
  /// trueの間のみ有効（nullなら広場全体の`Group.rolePriority`を使う、
  /// 2026-07-28追加、寄合ごとの個別ロール付与という以前の設計から変更）。
  final List<String>? rolePriorityOverride;

  /// 「この寄合独自の設定」トグル（2026-07-29追加）。trueの間、
  /// [rolePriorityOverride]・[readReceiptsEnabledOverride]・自分の通知オフ
  /// （`ConversationPrefs.roomNotificationOverrides`）が、広場全体の設定
  /// （`Group.rolePriority`/`Group.readReceiptsEnabled`/`ConversationPrefs.
  /// notificationsMuted`）より優先して適用される。falseの間は広場全体の
  /// 設定がそのまま使われ、この寄合固有の値は保存されていても無視される。
  /// 既存データ（この機能追加前に`rolePriorityOverride`を設定していた寄合）は
  /// fromJsonでtrue扱いにし、既存の上書き適用を維持する。
  final bool customSettingsEnabled;

  /// この寄合限定での既読機能オン/オフの上書き。[customSettingsEnabled]が
  /// trueの間のみ有効（nullなら広場全体の`Group.readReceiptsEnabled`を使う、
  /// 2026-07-29追加）。
  final bool? readReceiptsEnabledOverride;

  /// 寄合一覧の並び順（作成順）に使う。
  final Timestamp? createdAt;

  /// この寄合の削除を実行中の長・モデレーターのuserId。nullなら削除中で
  /// ない通常状態。削除操作の間だけ立てるマーカーで、これが立っている間は
  /// メンバーなら誰でもこの寄合のメッセージを物理削除できる
  /// （`GroupRepository.deleteRoom`、firestore.rules参照）。
  final String? roomDeletionRequestedBy;

  /// ピン留めされたメッセージidの一覧。配列の末尾が最後にピン留めしたもの
  /// （表示時は逆順にして新しいピン留めを上に出す）。
  final List<String> pinnedMessageIds;

  factory Room.fromJson(String roomId, Map<String, dynamic> json) {
    final priorityOverrideJson = json['rolePriorityOverride'];
    final pinnedJson = json['pinnedMessageIds'];
    return Room(
      roomId: roomId,
      groupId: json['groupId'] as String,
      name: json['name'] as String,
      memberIds: List<String>.from(json['memberIds'] as List),
      lastMessageAt: json['lastMessageAt'] as Timestamp?,
      createdAt: json['createdAt'] as Timestamp?,
      roomDeletionRequestedBy: json['roomDeletionRequestedBy'] as String?,
      rolePriorityOverride: priorityOverrideJson is List
          ? List<String>.from(priorityOverrideJson)
          : null,
      // 既存データ（この機能追加前に作られた寄合）は、rolePriorityOverride
      // が既に設定されていればtrue扱いにして従来の上書き適用を維持する。
      customSettingsEnabled:
          json['customSettingsEnabled'] as bool? ??
          (priorityOverrideJson is List),
      readReceiptsEnabledOverride: json['readReceiptsEnabledOverride'] as bool?,
      pinnedMessageIds: pinnedJson is List
          ? List<String>.from(pinnedJson)
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'name': name,
      'memberIds': memberIds,
      'lastMessageAt': lastMessageAt,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'roomDeletionRequestedBy': roomDeletionRequestedBy,
      'rolePriorityOverride': rolePriorityOverride,
      'customSettingsEnabled': customSettingsEnabled,
      'readReceiptsEnabledOverride': readReceiptsEnabledOverride,
      'pinnedMessageIds': pinnedMessageIds,
    };
  }
}
