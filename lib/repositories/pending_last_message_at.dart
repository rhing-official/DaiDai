import 'package:cloud_firestore/cloud_firestore.dart';

/// 語らい（一対・広場）の文書の`data()`を返す。送信直後で、`lastMessageAt`が
/// `FieldValue.serverTimestamp()`の書き込み待ちの間だけ、`lastMessageAt`を現在時刻にして返す
/// （2026-11-27）。
///
/// 書き込み待ちの間、Firestoreのローカルの結果では、このフィールドが`null`になる。一覧は
/// `lastMessageAt`の降順で並べる為、送信した語らいが一度、「一度も送っていない語らい」と同じく
/// 一番下へ落ち、サーバーの確定後に一番上へ戻っていた（選択の枠も、一番下へ滑ってから上がって
/// いた）。キーが有るのに値が`null`で、かつ書き込み待ちの時だけ、現在時刻で補う。キーが無い
/// （まだ一度も送っていない）語らいは、そのまま。
Map<String, dynamic> dataWithPendingLastMessageAt(
  DocumentSnapshot<Map<String, dynamic>> doc,
) {
  final data = doc.data()!;
  if (doc.metadata.hasPendingWrites &&
      data.containsKey('lastMessageAt') &&
      data['lastMessageAt'] == null) {
    return {...data, 'lastMessageAt': Timestamp.now()};
  }
  return data;
}
