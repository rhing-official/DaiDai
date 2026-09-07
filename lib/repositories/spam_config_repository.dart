import 'package:cloud_firestore/cloud_firestore.dart';

/// クライアント側スパムチェック（技術仕様書8.3レイヤー3）用の設定を扱う
/// リポジトリ（2026-09-07追加）。メッセージ内容自体はサーバー側で監視せず、
/// ここで取得したキーワード一覧を端末側で照合するだけに留める
/// （`lib/utils/spam_check.dart`参照）。
abstract class SpamConfigRepository {
  /// `config/spamKeywords`（単一ドキュメント、`keywords`配列フィールド）を
  /// 監視する。未作成の場合は空リストを返す。
  Stream<List<String>> watchSpamKeywords();

  /// クライアント側スパムチェック（レイヤー3）の警告ダイアログで、
  /// ユーザーが「やめる」を選んで送信を取りやめたことをメタデータのみ
  /// （本文は含めない）で記録する。技術仕様書8.4の段階的アカウント停止の
  /// 判定材料の1つになる（`functions/src/index.ts`の
  /// `onSpamViolationCreated`参照）。
  Future<void> reportSpamWarningDeclined({
    required String userId,
    String? conversationId,
  });
}

class FirestoreSpamConfigRepository implements SpamConfigRepository {
  FirestoreSpamConfigRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Stream<List<String>> watchSpamKeywords() {
    return _firestore.collection('config').doc('spamKeywords').snapshots().map((
      doc,
    ) {
      final keywords = doc.data()?['keywords'];
      if (keywords is! List) return const [];
      return keywords.whereType<String>().toList();
    });
  }

  @override
  Future<void> reportSpamWarningDeclined({
    required String userId,
    String? conversationId,
  }) {
    return _firestore.collection('spamViolations').add({
      'userId': userId,
      'kind': 'keywordDeclined',
      'conversationId': conversationId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
