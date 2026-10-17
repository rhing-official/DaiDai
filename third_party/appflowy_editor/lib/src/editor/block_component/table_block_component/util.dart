import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

Node? getCellNode(Node tableNode, int col, int row) {
  return tableNode.children.firstWhereOrNull(
    (n) =>
        n.attributes[TableCellBlockKeys.colPosition] == col &&
        n.attributes[TableCellBlockKeys.rowPosition] == row,
  );
}

extension TableCellNodeDynamicExtension on dynamic {
  double toDouble({double defaultValue = 0.0}) {
    if (this is int) {
      return this.toDouble();
    } else if (this is double) {
      return this;
    } else {
      return double.tryParse(toString()) ?? defaultValue;
    }
  }
}

extension TableCellNodeAttributesExtension on Node {
  double get cellWidth {
    assert(type == TableCellBlockKeys.type);
    return attributes[TableCellBlockKeys.width]?.toDouble() ??
        TableDefaults.colWidth;
  }

  double get cellHeight {
    assert(type == TableCellBlockKeys.type);
    return attributes[TableCellBlockKeys.height]?.toDouble() ??
        TableDefaults.rowHeight;
  }

  double get colHeight {
    assert(type == TableBlockKeys.type);
    return attributes[TableBlockKeys.colsHeight]?.toDouble() ??
        TableDefaults.rowHeight;
  }
}

/// タッチ操作が主体のプラットフォームか（DaiDai patch、2026-10-17）。表の行・列
/// ハンドルと「+」ボタンはマウスのホバーで出す作りのため、タッチでは出す
/// きっかけが無かった。タッチ主体の端末では、表の中にカーソルがある間は
/// 常時表示し、並び替えも長押しドラッグで起動する。テストでは
/// `debugDefaultTargetPlatformOverride`で切り替えられる。
bool get isTableTouchPlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// [selection]の端が表[table]の中にあるか（表の中にカーソル・選択がある間は
/// その表を「操作中」とみなす、DaiDai patch、2026-10-17）。
bool isSelectionInTable(Node table, Selection? selection) {
  if (selection == null) {
    return false;
  }
  bool inside(Path path) {
    final tablePath = table.path;
    if (path.length < tablePath.length) {
      return false;
    }
    for (var i = 0; i < tablePath.length; i++) {
      if (path[i] != tablePath[i]) {
        return false;
      }
    }
    return true;
  }

  return inside(selection.start.path) || inside(selection.end.path);
}

/// タッチ主体の端末で、[table]の中に選択がある間だけ[builder]へ`true`を渡す
/// （DaiDai patch、2026-10-17）。タッチ主体でない端末では常に`false`。
class TableTouchActiveBuilder extends StatelessWidget {
  const TableTouchActiveBuilder({
    super.key,
    required this.table,
    required this.editorState,
    required this.builder,
  });

  final Node table;
  final EditorState editorState;
  final Widget Function(BuildContext context, bool active) builder;

  @override
  Widget build(BuildContext context) {
    if (!isTableTouchPlatform) {
      return builder(context, false);
    }
    return ValueListenableBuilder<Selection?>(
      valueListenable: editorState.selectionNotifier,
      builder: (context, selection, _) =>
          builder(context, isSelectionInTable(table, selection)),
    );
  }
}
