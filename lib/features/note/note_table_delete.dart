import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// 表全体が範囲選択されている時にBackspace/Deleteで表ごと消すためのコマンド
/// （2026-10-04追加、ユーザー指示）。
///
/// `appflowy_editor`の標準の`deleteSelection`は、表のセルとその中身を
/// 決して消さない設計（コメントにも「table nodes should be deleted using the
/// table menu」とある）のため、全セルを選択しても中のテキストだけが消えて
/// 表の枠が残っていた。ライブラリ本体は触らず、標準のBackspace/Deleteの
/// **前**に置くコマンドとして、「全セルを覆う範囲選択」の場合だけ表を
/// ノードごと削除する。該当しなければ`ignored`を返し、従来どおり標準の処理へ
/// 進む（一部のセルだけの選択は従来どおりセル内のテキストだけが消える）。
final CommandShortcutEvent wholeTableBackspaceCommand = CommandShortcutEvent(
  key: 'delete fully selected tables (backspace)',
  getDescription: () => 'Delete fully selected tables',
  command: 'backspace, shift+backspace',
  handler: deleteFullySelectedTables,
);

final CommandShortcutEvent wholeTableDeleteCommand = CommandShortcutEvent(
  key: 'delete fully selected tables (delete)',
  getDescription: () => 'Delete fully selected tables',
  command: 'delete, shift+delete',
  handler: deleteFullySelectedTables,
);

KeyEventResult deleteFullySelectedTables(EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null || selection.isCollapsed) {
    return KeyEventResult.ignored;
  }
  // ブロック選択・全選択は標準の処理に任せる。
  if (editorState.selectionType == SelectionType.block ||
      editorState.selectionUpdateReason == SelectionUpdateReason.selectAll) {
    return KeyEventResult.ignored;
  }
  final normalized = selection.normalized;
  final tables = fullyCoveredTables(editorState, normalized);
  if (tables.isNotEmpty) {
    unawaited(_deleteTables(editorState, normalized, tables));
    return KeyEventResult.handled;
  }
  // 行全体・列全体を覆う選択は、その行/列を削除する（2026-10-04追加、
  // ユーザー指示）。
  final lines = fullySelectedLines(editorState, normalized);
  if (lines == null) return KeyEventResult.ignored;
  unawaited(_deleteLines(editorState, lines));
  return KeyEventResult.handled;
}

/// 選択が覆っている、表の連続した行（または列）。
class SelectedTableLines {
  const SelectedTableLines({
    required this.table,
    required this.direction,
    required this.from,
    required this.to,
  });

  final Node table;
  final TableDirection direction;

  /// 削除対象のインデックス範囲（両端を含む）。
  final int from;
  final int to;
}

/// [selection]（正規化済み）が**同じ表の2つの別々のセル**にまたがり、その
/// 矩形が全列を覆う（行の削除）／全行を覆う（列の削除）場合にその範囲を返す。
/// 全行・全列を覆う場合（表全体）や一部のセルだけの場合、同じセル内の選択、
/// 表の外へ出る選択はnull（呼び出し側で表ごと削除／標準処理になる）。
/// セル単位の判定で、段落内のオフセットは問わない（表全体の選択と同じ規則）。
SelectedTableLines? fullySelectedLines(
  EditorState editorState,
  Selection selection,
) {
  Node? cellOf(Position position) {
    final node = editorState.getNodeAtPath(position.path);
    final cell = node?.findParent((n) => n.type == TableCellBlockKeys.type);
    return cell ?? (node?.type == TableCellBlockKeys.type ? node : null);
  }

  final startCell = cellOf(selection.start);
  final endCell = cellOf(selection.end);
  if (startCell == null || endCell == null || startCell.id == endCell.id) {
    return null;
  }
  final table = startCell.parent;
  if (table == null ||
      table.type != TableBlockKeys.type ||
      endCell.parent?.id != table.id) {
    return null;
  }
  final rowsLen = table.attributes[TableBlockKeys.rowsLen];
  final colsLen = table.attributes[TableBlockKeys.colsLen];
  int? attr(Node cell, String key) {
    final value = cell.attributes[key];
    return value is int ? value : null;
  }

  final r1 = attr(startCell, TableCellBlockKeys.rowPosition);
  final r2 = attr(endCell, TableCellBlockKeys.rowPosition);
  final c1 = attr(startCell, TableCellBlockKeys.colPosition);
  final c2 = attr(endCell, TableCellBlockKeys.colPosition);
  if (rowsLen is! int ||
      colsLen is! int ||
      r1 == null ||
      r2 == null ||
      c1 == null ||
      c2 == null) {
    return null;
  }
  final rowMin = r1 < r2 ? r1 : r2;
  final rowMax = r1 < r2 ? r2 : r1;
  final colMin = c1 < c2 ? c1 : c2;
  final colMax = c1 < c2 ? c2 : c1;
  final coversAllCols = colMin == 0 && colMax == colsLen - 1;
  final coversAllRows = rowMin == 0 && rowMax == rowsLen - 1;
  if (coversAllCols && !coversAllRows) {
    return SelectedTableLines(
      table: table,
      direction: TableDirection.row,
      from: rowMin,
      to: rowMax,
    );
  }
  if (coversAllRows && !coversAllCols) {
    return SelectedTableLines(
      table: table,
      direction: TableDirection.col,
      from: colMin,
      to: colMax,
    );
  }
  return null;
}

Future<void> _deleteLines(
  EditorState editorState,
  SelectedTableLines lines,
) async {
  final table = lines.table;
  // 大きいインデックスから消す（先に小さい方を消すと残りのインデックスが
  // ずれるため）。`TableActions.delete`はメニューの「削除」と同じ処理。
  for (var i = lines.to; i >= lines.from; i--) {
    TableActions.delete(table, i, editorState, lines.direction);
    await Future<void>.delayed(Duration.zero);
  }
  if (table.parent == null) return;
  // 削除した位置の近傍の、残ったセルの先頭へカーソルを置く。
  final isRow = lines.direction == TableDirection.row;
  final remaining =
      table.attributes[isRow ? TableBlockKeys.rowsLen : TableBlockKeys.colsLen];
  if (remaining is! int || remaining <= 0) return;
  final index = lines.from < remaining ? lines.from : remaining - 1;
  final cell = table.children.where((c) {
    final row = c.attributes[TableCellBlockKeys.rowPosition];
    final col = c.attributes[TableCellBlockKeys.colPosition];
    return isRow ? (row == index && col == 0) : (row == 0 && col == index);
  }).firstOrNull;
  final leaf = cell == null ? null : _firstTextLeaf(cell);
  if (leaf != null) {
    editorState.selection = Selection.collapsed(Position(path: leaf.path));
  }
}

/// [selection]（正規化済み）に「全セルが覆われている」表を、文書順で返す。
///
/// セル単位の判定: 選択の始点が最初のテキスト（先頭セルの先頭段落）以前、
/// 終点が最後のテキスト（末尾セルの末尾段落）以後。UI上の複数セル選択は
/// セル単位の枠線オーバーレイで見せているため、先頭/末尾の段落内の
/// オフセットは問わない。ただし表全体が1つの段落しか持たない（1×1の表）
/// 場合は、段落内の一部を選んだだけで表が消えないよう、先頭〜末尾まで
/// 完全に覆われている時だけ対象にする。
List<Node> fullyCoveredTables(EditorState editorState, Selection selection) {
  final nodes = editorState.getNodesInSelection(selection);
  final tables = <Node>[];
  final seen = <String>{};
  for (final node in nodes) {
    final table = node.type == TableBlockKeys.type
        ? node
        : node.findParent((n) => n.type == TableBlockKeys.type);
    if (table == null || !seen.add(table.id)) continue;
    if (_coversWholeTable(table, selection)) tables.add(table);
  }
  tables.sort((a, b) => a.path < b.path ? -1 : 1);
  return tables;
}

bool _coversWholeTable(Node table, Selection selection) {
  final first = _firstTextLeaf(table);
  final last = _lastTextLeaf(table);
  if (first == null || last == null) return false;
  final start = selection.start;
  final end = selection.end;
  final startsBefore =
      start.path < first.path ||
      (start.path.equals(first.path) &&
          (first.path.equals(last.path) ? start.offset == 0 : true));
  final endsAfter =
      end.path > last.path ||
      (end.path.equals(last.path) &&
          (first.path.equals(last.path)
              ? end.offset >= (last.delta?.length ?? 0)
              : true));
  return startsBefore && endsAfter;
}

Node? _firstTextLeaf(Node node) {
  if (node.delta != null) return node;
  for (final child in node.children) {
    final leaf = _firstTextLeaf(child);
    if (leaf != null) return leaf;
  }
  return null;
}

Node? _lastTextLeaf(Node node) {
  if (node.delta != null) return node;
  for (final child in node.children.toList().reversed) {
    final leaf = _lastTextLeaf(child);
    if (leaf != null) return leaf;
  }
  return null;
}

bool _isInside(Node table, Position position) {
  final tablePath = table.path;
  if (position.path.length < tablePath.length) return false;
  for (var i = 0; i < tablePath.length; i++) {
    if (position.path[i] != tablePath[i]) return false;
  }
  return true;
}

Future<void> _deleteTables(
  EditorState editorState,
  Selection selection,
  List<Node> tables,
) async {
  final start = selection.start;
  final end = selection.end;
  final startTable = tables.where((t) => _isInside(t, start)).firstOrNull;
  final endTable = tables.where((t) => _isInside(t, end)).firstOrNull;

  // 表を消した後も残る、範囲の外側の端点（ノード参照で保持する。パスは
  // 削除後にずれるため、適用後に`node.path`で引き直す）。始点が表の内側なら
  // その表の次のテキスト、終点が表の内側ならその表の前のテキストへ寄せる。
  Node? remainingStartNode;
  var remainingStartOffset = 0;
  if (startTable == null) {
    remainingStartNode = editorState.getNodeAtPath(start.path);
    remainingStartOffset = start.offset;
  } else {
    final next = startTable.next;
    if (next != null && next.delta != null && !tables.contains(next)) {
      remainingStartNode = next;
    }
  }
  Node? remainingEndNode;
  var remainingEndOffset = 0;
  var endAtNodeEnd = false;
  if (endTable == null) {
    remainingEndNode = editorState.getNodeAtPath(end.path);
    remainingEndOffset = end.offset;
  } else {
    final previous = endTable.previous;
    if (previous != null && previous.delta != null) {
      remainingEndNode = previous;
      endAtNodeEnd = true;
    }
  }

  // カーソルの落とし先（残る範囲が無い場合）: 先頭の表の直前のテキスト末尾、
  // 無ければ最後の表の直後のテキスト先頭。
  final before = tables.first.previous;
  final after = tables.last.next;

  final transaction = editorState.transaction;
  for (final table in tables.reversed) {
    transaction.deleteNode(table);
  }
  // 文書が表だけだった場合、エディタが空になって操作不能にならないよう
  // 空の段落を残す。
  final root = editorState.document.root;
  final onlyTables =
      root.children.isNotEmpty &&
      root.children.every((child) => tables.contains(child));
  Node? placeholder;
  if (onlyTables) {
    placeholder = paragraphNode();
    transaction.insertNode([0], placeholder);
  }
  await editorState.apply(transaction);

  if (placeholder != null) {
    editorState.selection = Selection.collapsed(
      Position(path: placeholder.path),
    );
    return;
  }

  final startNode = remainingStartNode;
  final endNode = remainingEndNode;
  if (startNode != null && endNode != null && startNode.parent != null) {
    final remainingStart = Position(
      path: startNode.path,
      offset: remainingStartOffset,
    );
    final remainingEnd = Position(
      path: endNode.path,
      offset: endAtNodeEnd ? (endNode.delta?.length ?? 0) : remainingEndOffset,
    );
    final remaining = Selection(start: remainingStart, end: remainingEnd);
    if (!remaining.isCollapsed && !(remainingStart.path > remainingEnd.path)) {
      await editorState.deleteSelection(remaining);
      return;
    }
    editorState.selection = Selection.collapsed(remainingStart);
    return;
  }

  if (before != null && before.delta != null && before.parent != null) {
    editorState.selection = Selection.collapsed(
      Position(path: before.path, offset: before.delta!.length),
    );
  } else if (after != null && after.delta != null && after.parent != null) {
    editorState.selection = Selection.collapsed(Position(path: after.path));
  }
}
