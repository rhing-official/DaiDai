import 'package:cloud_firestore/cloud_firestore.dart';

/// 一対（DirectMessage） - 1対1の会話空間
class DirectMessage {
  const DirectMessage({
    required this.dmId,
    required this.participants,
    required this.participantRhingIds,
    required this.defaultRoomId,
    this.lastMessageAt,
    this.severanceRequestedBy,
    this.readReceiptsEnabled = true,
    this.readReceiptsProposalBy,
    this.accountDeletedUserId,
    this.roomsEnabled = true,
  });

  final String dmId;
  final List<String> participants;

  /// userId -> rhingId。一覧表示で相手の名前を出すための非正規化データ。
  final Map<String, String> participantRhingIds;
  final Timestamp? lastMessageAt;

  /// この一対の既定の寄合（`rooms`サブコレクション、`Group.defaultRoomId`と
  /// 同じ役割）。`getOrCreateDirectMessage`が作成時に必ず1件作る。
  final String defaultRoomId;

  /// 絶縁（双方合意による友達関係の解消・会話履歴の完全削除）を提案した側の
  /// userId。nullなら提案なし。提案した本人以外の参加者が同意すると、
  /// [DirectMessageRepository.acceptSeverance]がこのフラグを根拠に
  /// メッセージ・friends・friendRequests・この一対自体を物理削除する。
  final String? severanceRequestedBy;

  /// 既読機能のオン/オフ（一対共有の1つの設定。個人ごとの非公開設定では
  /// ない）。変更にはどちら向きも相手の承認が必要（[readReceiptsProposalBy]
  /// 参照）。
  final bool readReceiptsEnabled;

  /// 既読オン/オフの変更を提案した側のuserId。nullなら提案なし。提案は
  /// 常に「現在の[readReceiptsEnabled]を反転させる」ことを意味する
  /// （severanceRequestedByと同じ最小構成。
  /// [DirectMessageRepository.proposeReadReceiptsToggle]/
  /// `acceptReadReceiptsToggle`参照）。
  final String? readReceiptsProposalBy;

  /// アカウント削除により、この一対の相手が既に存在しなくなったことを示す
  /// マーカー。Cloud Functionsの定期削除処理が、削除されたユーザーの
  /// userIdをセットする。nullでなければ、もう一方の参加者が語らいを
  /// 完全削除できる（severanceRequestedByと同じ役割。firestore.rules参照）。
  final String? accountDeletedUserId;

  /// 複数の寄合（テキストチャンネル）を扱うか。falseの場合はサイドバーの
  /// 寄合一覧を出さず、`defaultRoomId`の1つだけを使う単一モード
  /// （2026-07-29追加）。一対は常にfalse（単一）で作られ、後から
  /// ハンバーガーメニューの「寄合を増やす」でtrueへの切り替えのみ可能
  /// （falseへは戻せない）。既存データ（この機能追加前に作られた一対）は
  /// 全てtrue扱いにする（fromJsonのデフォルト値、既存の複数寄合表示を
  /// 維持するため）。
  final bool roomsEnabled;

  /// 自分以外の参加者のuserId。
  String otherUserId(String currentUserId) {
    return participants.firstWhere((id) => id != currentUserId);
  }

  /// 自分以外の参加者のRhing ID。
  String otherRhingId(String currentUserId) {
    final otherId = otherUserId(currentUserId);
    return participantRhingIds[otherId] ?? otherId;
  }

  factory DirectMessage.fromJson(String dmId, Map<String, dynamic> json) {
    return DirectMessage(
      dmId: dmId,
      participants: List<String>.from(json['participants'] as List),
      participantRhingIds: Map<String, String>.from(
        json['participantRhingIds'] as Map? ?? {},
      ),
      defaultRoomId: json['defaultRoomId'] as String,
      lastMessageAt: json['lastMessageAt'] as Timestamp?,
      severanceRequestedBy: json['severanceRequestedBy'] as String?,
      readReceiptsEnabled: json['readReceiptsEnabled'] as bool? ?? true,
      readReceiptsProposalBy: json['readReceiptsProposalBy'] as String?,
      accountDeletedUserId: json['accountDeletedUserId'] as String?,
      roomsEnabled: json['roomsEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'participants': participants,
      'participantRhingIds': participantRhingIds,
      'defaultRoomId': defaultRoomId,
      'lastMessageAt': lastMessageAt,
      'severanceRequestedBy': severanceRequestedBy,
      'readReceiptsEnabled': readReceiptsEnabled,
      'readReceiptsProposalBy': readReceiptsProposalBy,
      'accountDeletedUserId': accountDeletedUserId,
      'roomsEnabled': roomsEnabled,
    };
  }

  /// 2人のuserIdから決定的なdmIdを作る（順序に依存しない）
  static String idFor(String userIdA, String userIdB) {
    final sorted = [userIdA, userIdB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }
}
