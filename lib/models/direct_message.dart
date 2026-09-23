import 'package:cloud_firestore/cloud_firestore.dart';

/// 一対（DirectMessage） - 1対1の会話空間
class DirectMessage {
  const DirectMessage({
    required this.dmId,
    required this.participants,
    required this.participantRhingSeeds,
    this.lastMessageAt,
    this.lastMessageSenderId,
    this.lastMessageContentType,
    this.lastMessagePreview,
    this.severanceRequestedBy,
    this.readReceiptsEnabled = true,
    this.readReceiptsProposalBy,
    this.accountDeletedUserId,
    this.roomsEnabled = false,
    this.roomOrder = const [],
  });

  final String dmId;
  final List<String> participants;

  /// userId -> rhingSeed。一覧表示で相手の名前を出すための非正規化データ。
  final Map<String, String> participantRhingSeeds;
  final Timestamp? lastMessageAt;

  /// 直近のメッセージを送信したuserId。語らい一覧の「未読優先」並べ替えで、
  /// 自分が送信した会話を未読扱いしないために使う（2026-09-02追加）。
  final String? lastMessageSenderId;

  /// [lastMessageAt]時点のメッセージの`Message.contentType`
  /// （text/image/video/file/sticker/call等）。語らい一覧のプレビュー表示で、
  /// テキスト以外は種類に応じたラベル（「[画像]」等）に変換するために使う
  /// （2026-09-02追加）。
  final String? lastMessageContentType;

  /// [lastMessageContentType]が`text`/`call`のときだけ入る、切り詰め済みの
  /// 本文プレビュー（`messageSnippetOf`）。それ以外の種類はnull
  /// （表示ラベルはロケール依存のためUI側で解決する、2026-09-02追加）。
  final String? lastMessagePreview;

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
  /// 寄合一覧を出さず、この一対が持つ唯一の寄合だけを使う単一モード
  /// （2026-07-29追加）。一対は常にfalse（単一）で作られ、ハンバーガー
  /// メニューの「寄合を増やす」でtrueへの切り替えができる。falseへ戻す
  /// （オフにする）ことも、寄合が1つだけの場合に限り可能（2026-09-14変更、
  /// 以前はtrueへの変更のみ許可する一方向仕様だった。あわせて独立していた
  /// `roomFeatureDisabled`フィールド——寄合の名前変更・削除メニューの
  /// 表示/非表示のみを切り替える3択目——は、この`roomsEnabled`のオン/オフ
  /// だけで十分と判断し廃止した）。fromJsonのデフォルト値はfalse
  /// （単一）: 一対はこの機能追加前から一貫して単一の会話構造しか
  /// 持たなかったため、フィールド欠落＝旧来通りの単一で問題ない。
  final bool roomsEnabled;

  /// 寄合一覧（サイドバー）の表示順（寄合idの並び、先頭が最上位、
  /// 2026-09-08追加）。ここに含まれない寄合（新規作成直後・機能追加前の
  /// 既存データ）は、従来通り`DmRoom.createdAt`順で末尾に追加される
  /// （呼び出し側`talks_tab.dart`が突き合わせる）。含まれていても既に
  /// 削除済みの寄合idは単に無視される。
  final List<String> roomOrder;

  /// 自分以外の参加者のuserId。
  String otherUserId(String currentUserId) {
    return participants.firstWhere((id) => id != currentUserId);
  }

  /// 自分以外の参加者のRhing Seed。
  String otherRhingSeed(String currentUserId) {
    final otherId = otherUserId(currentUserId);
    return participantRhingSeeds[otherId] ?? otherId;
  }

  factory DirectMessage.fromJson(String dmId, Map<String, dynamic> json) {
    return DirectMessage(
      dmId: dmId,
      participants: List<String>.from(json['participants'] as List),
      participantRhingSeeds: Map<String, String>.from(
        json['participantRhingSeeds'] as Map? ?? {},
      ),
      lastMessageAt: json['lastMessageAt'] as Timestamp?,
      lastMessageSenderId: json['lastMessageSenderId'] as String?,
      lastMessageContentType: json['lastMessageContentType'] as String?,
      lastMessagePreview: json['lastMessagePreview'] as String?,
      severanceRequestedBy: json['severanceRequestedBy'] as String?,
      readReceiptsEnabled: json['readReceiptsEnabled'] as bool? ?? true,
      readReceiptsProposalBy: json['readReceiptsProposalBy'] as String?,
      accountDeletedUserId: json['accountDeletedUserId'] as String?,
      roomsEnabled: json['roomsEnabled'] as bool? ?? false,
      roomOrder: List<String>.from(json['roomOrder'] as List? ?? const []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'participants': participants,
      'participantRhingSeeds': participantRhingSeeds,
      'lastMessageAt': lastMessageAt,
      'lastMessageSenderId': lastMessageSenderId,
      'lastMessageContentType': lastMessageContentType,
      'lastMessagePreview': lastMessagePreview,
      'severanceRequestedBy': severanceRequestedBy,
      'readReceiptsEnabled': readReceiptsEnabled,
      'readReceiptsProposalBy': readReceiptsProposalBy,
      'accountDeletedUserId': accountDeletedUserId,
      'roomsEnabled': roomsEnabled,
      'roomOrder': roomOrder,
    };
  }

  /// 2人のuserIdから決定的なdmIdを作る（順序に依存しない）
  static String idFor(String userIdA, String userIdB) {
    final sorted = [userIdA, userIdB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }
}
