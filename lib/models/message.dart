import 'package:cloud_firestore/cloud_firestore.dart';

/// メッセージを既読にしたユーザー1人分の記録。
class MessageReadReceipt {
  const MessageReadReceipt({required this.userId, this.readAt});

  final String userId;
  final Timestamp? readAt;

  factory MessageReadReceipt.fromJson(Map<String, dynamic> json) {
    return MessageReadReceipt(
      userId: json['userId'] as String,
      readAt: json['readAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {'userId': userId, 'readAt': readAt};
}

/// リアクションの固定絵文字セット（firestore.rulesの許可リストと必ず一致させること）。
const kReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// 返信の引用プレビュー用にcontentを切り詰める。
String messageSnippetOf(String content) {
  const maxLength = 80;
  final singleLine = content.replaceAll('\n', ' ');
  if (singleLine.length <= maxLength) return singleLine;
  return '${singleLine.substring(0, maxLength)}…';
}

class Message {
  const Message({
    required this.messageId,
    required this.conversationId,
    required this.conversationType,
    required this.senderId,
    this.senderRhingId,
    required this.content,
    required this.contentType,
    this.sentAt,
    this.hiddenFor = const [],
    this.silent = false,
    this.readBy = const [],
    this.replyToMessageId,
    this.replyToSenderId,
    this.replyToSenderRhingId,
    this.replyToSnippet,
    this.editedAt,
    this.reactions = const {},
    this.callStartedAt,
    this.callDurationSeconds,
    this.callIsVideo,
    this.accountDeletionResponse,
  });

  final String messageId;
  final String conversationId;
  final String conversationType; // dm | seat | room
  final String senderId;

  /// 送信者のRhing ID（グループ会話でアイコン・名前を表示するための非正規化）。
  final String? senderRhingId;
  final String content;
  // text | image | file | sticker | video | call | accountDeleted
  final String contentType;
  final Timestamp? sentAt;

  /// このメッセージを自分のアカウントから見えなくした（範囲選択削除した）
  /// ユーザーのuserId一覧。実際にはサーバーから削除せず、本人の画面にだけ
  /// 表示しない（他の参加者には引き続き見える）。会話の参加者全員が
  /// ここに含まれた時点で、クライアントがサーバーから物理削除する
  /// （`DirectMessageRepository.hideMessagesForMe`/
  /// `GroupRepository.hideRoomMessagesForMe`参照）。
  final List<String> hiddenFor;

  /// 送信者が「相手に通知せず送る」を選んだメッセージかどうか。
  /// FCMのプッシュ通知基盤が実装された際、このフラグが立っているメッセージは
  /// 通知を送らないようにする想定（実装内容.md参照）。
  final bool silent;

  /// このメッセージを読んだユーザーの一覧（送信者本人は含まない想定）。
  final List<MessageReadReceipt> readBy;

  /// 返信元メッセージのid。nullなら返信ではない通常メッセージ。
  final String? replyToMessageId;

  /// 返信元メッセージの送信者（送信時点の非正規化）。返信元が読み込み済み
  /// ウィンドウ外や送信取り消し済みでも引用プレビューを表示し続けるために持つ。
  /// 表示側（`_MessageRow`）は、現在ロード済みのリストに返信元の実物が
  /// あればそちらを優先し（最新の内容・編集済みラベルを反映できる）、
  /// 無ければこのフィールドにフォールバックする。
  final String? replyToSenderId;
  final String? replyToSenderRhingId;

  /// 返信元メッセージの本文スニペット（返信作成時点の内容、非正規化）。
  /// 返信元が送信取り消しされた場合は、`unsendMessage`/`unsendRoomMessage`が
  /// この引用メッセージ側のreplyTo系フィールドをまとめてクリアする
  /// （送信取り消しは相手側にも痕跡を残さない、という仕様のため）。
  final String? replyToSnippet;

  /// 編集済みの場合の最終編集日時。nullなら未編集。
  final Timestamp? editedAt;

  /// このメッセージへのリアクション。key=リアクションしたuserId、
  /// value=そのユーザーが付けている[kReactionEmojis]の絵文字一覧
  /// （2026-08-05変更、以前は1ユーザー1個までだったが、複数の異なる
  /// 絵文字を同時に付けられるよう変更した。同じ絵文字を選び直すと
  /// その絵文字だけ解除される）。
  final Map<String, List<String>> reactions;

  /// contentType='call'（通話履歴メッセージ）専用のフィールド。通話が実際に
  /// 接続した（応答された）場合のみ発信者側から送られる（不在着信・拒否は
  /// 対象外）。[content]には表示用のフォールバック文言（「通話が終了しました」）
  /// を入れておき、UI（`_MessageRow`）はこれらのフィールドがあれば専用の
  /// 通話サマリー表示に切り替える。
  final Timestamp? callStartedAt;
  final int? callDurationSeconds;
  final bool? callIsVideo;

  /// contentType='accountDeleted'（アカウント削除通知）専用フィールド。
  /// DMでのみ使う（広場では常にnull=表示のみで応答不要）。[senderId]には
  /// 削除されたユーザーのuserIdをそのまま入れる（'call'タイプが発信者の
  /// userIdをsenderIdに使うのと同じ考え方）。相手が「いいえ」を選ぶと
  /// 'declined'になり、以後はい/いいえボタンを表示しなくなる（「はい」の
  /// 場合はDM自体が物理削除されるため状態を持つ必要が無い）。
  final String? accountDeletionResponse;

  factory Message.fromJson(String messageId, Map<String, dynamic> json) {
    return Message(
      messageId: messageId,
      conversationId: json['conversationId'] as String,
      conversationType: json['conversationType'] as String,
      senderId: json['senderId'] as String,
      senderRhingId: json['senderRhingId'] as String?,
      content: json['content'] as String,
      contentType: json['contentType'] as String,
      sentAt: json['sentAt'] as Timestamp?,
      hiddenFor: (json['hiddenFor'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      silent: json['silent'] as bool? ?? false,
      readBy: (json['readBy'] as List<dynamic>? ?? [])
          .map((e) => MessageReadReceipt.fromJson(e as Map<String, dynamic>))
          .toList(),
      replyToMessageId: json['replyToMessageId'] as String?,
      replyToSenderId: json['replyToSenderId'] as String?,
      replyToSenderRhingId: json['replyToSenderRhingId'] as String?,
      replyToSnippet: json['replyToSnippet'] as String?,
      editedAt: json['editedAt'] as Timestamp?,
      // 旧形式（reactions.$userIdが単一の絵文字文字列）のドキュメントも
      // 引き続き読めるよう、Listでなければ1要素のListに包む
      // （後方互換。書き込みは常にListで行うため、この分岐は既存データの
      // 読み込み時のみ通る）。
      reactions: (json['reactions'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(
          key,
          value is List
              ? value.map((e) => e as String).toList()
              : [value as String],
        ),
      ),
      callStartedAt: json['callStartedAt'] as Timestamp?,
      callDurationSeconds: json['callDurationSeconds'] as int?,
      callIsVideo: json['callIsVideo'] as bool?,
      accountDeletionResponse: json['accountDeletionResponse'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conversationId': conversationId,
      'conversationType': conversationType,
      'senderId': senderId,
      'senderRhingId': senderRhingId,
      'content': content,
      'contentType': contentType,
      'sentAt': sentAt ?? FieldValue.serverTimestamp(),
      'hiddenFor': hiddenFor,
      'readBy': <Map<String, dynamic>>[],
      'isSpam': false,
      'silent': silent,
      'replyToMessageId': replyToMessageId,
      'replyToSenderId': replyToSenderId,
      'replyToSenderRhingId': replyToSenderRhingId,
      'replyToSnippet': replyToSnippet,
      'editedAt': editedAt,
      'reactions': reactions,
      'callStartedAt': callStartedAt,
      'callDurationSeconds': callDurationSeconds,
      'callIsVideo': callIsVideo,
      'accountDeletionResponse': accountDeletionResponse,
    };
  }
}
