import 'package:cloud_firestore/cloud_firestore.dart';

/// 共有ノートのリアルタイム共同編集用の操作ログ（2026-09-09追加）。
/// `notes/{noteId}/ops/{opId}`に保存される。1件のドキュメントには、送信側の
/// 短いデバウンス窓内に発生した複数の`Transaction`（appflowy_editorの
/// `Transaction.toJson()`相当）をまとめて配列で持つ（`note_transaction_codec.dart`
/// でエンコード/デコードする）。[sessionId]は送信元クライアントがノートを
/// 開いている間だけ有効なランダムIDで、受信側が「自分が送った操作」を
/// 二重適用しないためのエコー判定に使う。
class NoteOp {
  const NoteOp({
    required this.opId,
    required this.transactions,
    required this.sessionId,
    required this.authorId,
    this.createdAt,
  });

  final String opId;
  final List<Map<String, dynamic>> transactions;
  final String sessionId;
  final String authorId;
  final Timestamp? createdAt;

  factory NoteOp.fromJson(String opId, Map<String, dynamic> json) {
    return NoteOp(
      opId: opId,
      transactions: ((json['transactions'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
      sessionId: json['sessionId'] as String? ?? '',
      authorId: json['authorId'] as String? ?? '',
      createdAt: json['createdAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {
    'transactions': transactions,
    'sessionId': sessionId,
    'authorId': authorId,
    'createdAt': createdAt ?? FieldValue.serverTimestamp(),
  };
}
