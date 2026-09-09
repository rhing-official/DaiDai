import 'package:appflowy_editor/appflowy_editor.dart';

/// 共有ノートのリアルタイム共同編集（`note_pane_view.dart`）で、
/// appflowy_editorの`Transaction`をFirestoreへ保存可能なJSONへ変換/復元する
/// ためのユーティリティ（2026-09-09追加）。
///
/// appflowy_editorパッケージ自体には`Transaction.fromJson`や`Operation`種別を
/// 振り分けるディスパッチャが存在しない（`Operation.fromJson()`は
/// `UnimplementedError`を投げるのみ）ため、ここで自前に実装する。
///
/// **重要**: パッケージ側の`InsertOperation.fromJson`等は`json['path'] as Path`
/// （`Path`は`List<int>`のtypedef）という直接キャストをしており、
/// `List<int>`はFirestore/`jsonDecode`から読み返した`List<dynamic>`に対しては
/// 実行時型エラーになる（`List<dynamic> is List<int>`は偽）。同様に
/// `Node.fromJson`は`Map<String, Object>`を受け取る宣言だが、Firestoreから
/// 読み返したデータは`Map<String, dynamic>`であり、これも実行時型エラーになる
/// （`Map<String, dynamic> is Map<String, Object>`は偽）。そのためこのファイルは
/// パッケージの`fromJson`系メソッドを経由せず、`Operation`/`Node`の
/// コンストラクタを直接呼び、パス・属性・子ノードを都度`List<int>`/
/// `Map<String, dynamic>`へ明示的に正規化してから渡す。
Map<String, dynamic> encodeTransaction(Transaction transaction) =>
    transaction.toJson();

/// [json]（`encodeTransaction`が返したものをFirestore経由で読み返した形）から
/// `Transaction`を復元する。[document]は`Transaction`のコンストラクタに必須の
/// フィールドだが、`EditorState.apply`は`transaction.operations`のみを見るため
/// 実質未使用（呼び出し側は`editorState.document`を渡せば十分）。
Transaction decodeTransaction(Document document, Map<String, dynamic> json) {
  final operationsJson = (json['operations'] as List?) ?? const [];
  final transaction = Transaction(document: document);
  transaction.operations = operationsJson
      .map((e) => _decodeOperation((e as Map).cast<String, dynamic>()))
      .toList();
  return transaction;
}

Path _decodePath(Object? raw) {
  return (raw as List).map((e) => (e as num).toInt()).toList();
}

Node _decodeNode(Map<String, dynamic> json) {
  final node = Node(
    type: json['type'] as String,
    attributes: Map<String, dynamic>.from(
      (json['data'] as Map?)?.cast<String, dynamic>() ?? {},
    ),
    children: ((json['children'] as List?) ?? const [])
        .map((e) => _decodeNode((e as Map).cast<String, dynamic>()))
        .toList(),
  );
  for (final child in node.children) {
    child.parent = node;
  }
  return node;
}

Operation _decodeOperation(Map<String, dynamic> json) {
  final path = _decodePath(json['path']);
  switch (json['op'] as String?) {
    case 'insert':
      final nodes = ((json['nodes'] as List?) ?? const [])
          .map((n) => _decodeNode((n as Map).cast<String, dynamic>()))
          .toList();
      return InsertOperation(path, nodes);
    case 'delete':
      final nodes = ((json['nodes'] as List?) ?? const [])
          .map((n) => _decodeNode((n as Map).cast<String, dynamic>()))
          .toList();
      return DeleteOperation(path, nodes);
    case 'update':
      final attributes = Map<String, dynamic>.from(
        (json['attributes'] as Map?)?.cast<String, dynamic>() ?? {},
      );
      final oldAttributes = Map<String, dynamic>.from(
        (json['oldAttributes'] as Map?)?.cast<String, dynamic>() ?? {},
      );
      return UpdateOperation(path, attributes, oldAttributes);
    case 'update_text':
      final delta = Delta.fromJson((json['delta'] as List?) ?? const []);
      final inverted = Delta.fromJson((json['inverted'] as List?) ?? const []);
      return UpdateTextOperation(path, delta, inverted);
    default:
      throw FormatException('Unknown operation type: ${json['op']}');
  }
}
