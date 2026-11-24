import '../models/message.dart';

/// 既読の表示（✓の人数・既読者一覧）から、削除済みのアカウントを除く（2026-11-24）。
///
/// [isDeleted]は、削除済みと確定した時だけ`true`を返す。読み込み中で分からない人は`false`
/// にして残す（開いた瞬間に、✓や人数が点滅するのを避けるため）。メッセージの`readBy`の記録
/// 自体は変えない。広場を抜けただけの人は削除していないので、残す。
List<MessageReadReceipt> withoutDeletedReaders(
  List<MessageReadReceipt> readers,
  bool Function(String userId) isDeleted,
) => [
  for (final reader in readers)
    if (!isDeleted(reader.userId)) reader,
];
