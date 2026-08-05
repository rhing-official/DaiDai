import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/gekiga/gekiga_colors.dart';
import 'monochrome_box.dart';

/// [GekigaTileContent]で使う「アイコン＋タイトル／サブタイトル＋末尾
/// ウィジェット」のタップ可能なRow。外枠（手描き風ジグザグ矩形）は
/// [GekigaJointedTileList]・[GekigaJointedPair]のように、複数の箱を
/// まとめて描く側が別途描く（2026-08-04、単体で外枠を持つ`GekigaPanelBox`/
/// `GekigaMenuTile`は、隣接ブロックの接合デザイン導入に伴い全ての
/// 呼び出し元を`GekigaJointedTileList`等へ置き換えたため削除した）。
class GekigaTileContent extends StatelessWidget {
  const GekigaTileContent({
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? GekigaColors.panel : GekigaColors.onPanel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: _gekigaTileContent(
          context: context,
          fg: fg,
          leading: leading,
          title: title,
          subtitle: subtitle,
          trailing: trailing,
        ),
      ),
    );
  }
}

/// [GekigaTileContent]で使う「アイコン＋タイトル／サブタイトル＋末尾
/// ウィジェット」のレイアウト。
///
/// パディング・フォントサイズは、シンプルスタイルの`ListTile`が実際に
/// 使う値に揃えている（2026-08-04変更。以前はvertical:24等、独自の
/// 大きめの値を試行錯誤していたが、シンプル/劇画スタイルの切り替えで
/// ブロックの縦幅・座標・文字サイズが変わってしまうとの指摘を受けた）。
/// `ListTile`は`contentPadding`をそのまま高さに反映するのではなく、
/// 1行なら56dp・2行なら72dpという最小高さを内部で強制するため
/// （`contentPadding: horizontal:16, vertical:8`が既定でも実際の見た目は
/// この最小高さぶん中央寄せされる）、ここではその強制後の実効値
/// （縦: 概ね(56-24)/2=16、横: 16）を直接使う。フォントサイズも
/// `ListTile.title`/`ListTile.subtitle`の既定と同じ`titleMedium`/
/// `bodyMedium`にする（`AppTheme`/`GekigaTheme`とも既定のMaterial
/// テキストテーマをそのまま使っているため、両スタイルで同じサイズになる）。
Widget _gekigaTileContent({
  required BuildContext context,
  required Color fg,
  required Widget? leading,
  required Widget title,
  required Widget? subtitle,
  required Widget? trailing,
}) {
  final textTheme = Theme.of(context).textTheme;
  return Padding(
    // 横方向は12（2026-08-05変更、以前は20→16の順で拡げていたが、名前を
    // 一定文字数で切るようにしたことでテキストが十分短くなり、逆に余白が
    // 文字に対して広すぎるとの指摘を受けたため詰めた）。縦方向は
    // 上記の`ListTile`高さ整合のため16のまま変更しない。
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[
          IconTheme.merge(
            data: IconThemeData(color: fg),
            child: leading,
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(
                style: textTheme.titleMedium?.copyWith(color: fg),
                child: title,
              ),
              if (subtitle != null)
                DefaultTextStyle.merge(
                  style: textTheme.bodyMedium?.copyWith(
                    color: fg.withValues(alpha: 0.75),
                  ),
                  child: subtitle,
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          IconTheme.merge(
            data: IconThemeData(color: fg),
            child: trailing,
          ),
        ],
      ],
    ),
  );
}

/// [GekigaTileContent]のボタン版。アイコン付き横並びの内容ではなく、
/// ボタンらしいテキスト（＋任意のアイコン）を返す。単体で使う場合は
/// `GekigaJointedTileList(seeds: [seed], selectedFlags: [selected], children: [GekigaButton(...)])`
/// のように要素数1のリストとして渡し、[_GekigaJointedList]のモノクロ
/// ボックス描画をそのまま「単体の枠付きボタン」として再利用する
/// （2026-08-04新規、身だしなみの保存/削除/追加ボタン向け）。[selected]は
/// 選択状態ではなく、他の劇画UI要素と同じ「選択中=白地黒文字／未選択=黒地
/// 白文字」のルールをボタンの強弱表現に転用したもの（true＝主要操作、
/// false＝副次的操作）。
class GekigaButton extends StatelessWidget {
  const GekigaButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? GekigaColors.panel : GekigaColors.onPanel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: fg, size: 18),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(color: fg, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [GekigaJointedTileList]・[GekigaJointedPair]で使う、複数の箱を並べる
/// 実装本体（2026-08-04追加、2026-08-05に「隙間なく接する」設計から
/// 「各箱を独立させ、間に[_gap]を空ける」設計へ変更。可変幅の箱同士を
/// 無理に接合させるとサイズ調整や見た目の破綻が起きやすく、素直に間隔を
/// 空けたほうが単純で確実という判断）。
///
/// 各箱は直角の矩形で、`MonochromeBoxPainter`（ホーム画面ナビチップ等の
/// 「メニューチップ」と同じ黒外枠→白内枠→塗り色の3層）で描く
/// （2026-08-05、独自の塗り1色＋線1色描画から変更。以前は黒枠がほとんど
/// 見えなかった不具合の原因）。角の形は変えず、代わりに箱ごとの`seed`で
/// 枠の太さを僅かに変化させることで些細な手作り感を出す
/// （[MonochromeBoxPainter]参照）。
class _GekigaJointedList extends MultiChildRenderObjectWidget {
  const _GekigaJointedList({
    required this.axis,
    required this.seeds,
    required this.selectedFlags,
    required super.children,
  });

  final Axis axis;
  final List<int> seeds;
  final List<bool> selectedFlags;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderGekigaJointedList(
      axis: axis,
      seeds: seeds,
      selectedFlags: selectedFlags,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderGekigaJointedList renderObject,
  ) {
    renderObject
      ..axis = axis
      ..seeds = seeds
      ..selectedFlags = selectedFlags;
  }
}

/// 語らい一覧・寄合一覧・プルダウン（設定/身だしなみのドリルダウン）で
/// 使う、縦積みの接合リスト。[GekigaMenuTile]の内容（アイコン＋テキスト
/// のRow）をそのまま[children]に渡す（タップ処理は各子に持たせる）。
class GekigaJointedTileList extends StatelessWidget {
  const GekigaJointedTileList({
    required this.seeds,
    required this.selectedFlags,
    required this.children,
    super.key,
  });

  final List<int> seeds;
  final List<bool> selectedFlags;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _GekigaJointedList(
      axis: Axis.vertical,
      seeds: seeds,
      selectedFlags: selectedFlags,
      children: children,
    );
  }
}

/// 一対/広場の切り替えタブ（[_CategoryTab]）用の、横並び2個専用の接合ペア。
class GekigaJointedPair extends StatelessWidget {
  const GekigaJointedPair({
    required this.leftSeed,
    required this.leftSelected,
    required this.left,
    required this.rightSeed,
    required this.rightSelected,
    required this.right,
    super.key,
  });

  final int leftSeed;
  final bool leftSelected;
  final Widget left;
  final int rightSeed;
  final bool rightSelected;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return _GekigaJointedList(
      axis: Axis.horizontal,
      seeds: [leftSeed, rightSeed],
      selectedFlags: [leftSelected, rightSelected],
      children: [left, right],
    );
  }
}

class _JointedParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderGekigaJointedList extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _JointedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _JointedParentData> {
  _RenderGekigaJointedList({
    required Axis axis,
    required List<int> seeds,
    required List<bool> selectedFlags,
  }) : _axis = axis,
       _seeds = seeds,
       _selectedFlags = selectedFlags;

  // 上記コンストラクタは`this._axis`等の初期化フォームにできない
  // （引数名`axis`とpublicなsetter`axis`が衝突するため）。lintの
  // `prefer_initializing_formals`は意図的に無視する。

  /// 箱同士の間隔（2026-08-05追加。接合を廃止した代わりに、隙間で
  /// それぞれの箱を独立して見せる）。
  static const double _gap = 8;

  /// 枠の太さの基準値（2026-08-05追加）。`MonochromeBoxPainter`の
  /// `thicknessBase`に箱自身のサイズ（`box.size.shortestSide`）を渡すと、
  /// 長い名前で箱が大きくなるほど枠まで太くなってしまい、一覧内で箱ごとに
  /// 枠の太さがバラつく不具合になっていた。箱のサイズに関わらず常にこの
  /// 固定値を使うことで、枠の太さを揃える。
  static const double _fixedThicknessBase = 48;

  Axis _axis;
  set axis(Axis value) {
    if (_axis == value) return;
    _axis = value;
    markNeedsLayout();
  }

  List<int> _seeds;
  set seeds(List<int> value) {
    if (listEquals(_seeds, value)) return;
    _seeds = value;
    markNeedsPaint();
  }

  List<bool> _selectedFlags;
  set selectedFlags(List<bool> value) {
    if (listEquals(_selectedFlags, value)) return;
    _selectedFlags = value;
    markNeedsPaint();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _JointedParentData) {
      child.parentData = _JointedParentData();
    }
  }

  List<RenderBox> _collectChildren() {
    final list = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      list.add(child);
      child = (child.parentData! as _JointedParentData).nextSibling;
    }
    return list;
  }

  @override
  void performLayout() {
    final vertical = _axis == Axis.vertical;
    final loose = vertical
        ? BoxConstraints(maxWidth: constraints.maxWidth)
        : BoxConstraints(maxHeight: constraints.maxHeight);
    var main = 0.0;
    var cross = 0.0;
    var isFirst = true;
    var child = firstChild;
    while (child != null) {
      child.layout(loose, parentUsesSize: true);
      if (!isFirst) main += _gap;
      isFirst = false;
      final childParentData = child.parentData! as _JointedParentData;
      childParentData.offset = vertical ? Offset(0, main) : Offset(main, 0);
      final childSize = child.size;
      main += vertical ? childSize.height : childSize.width;
      final childCross = vertical ? childSize.width : childSize.height;
      if (childCross > cross) cross = childCross;
      child = childParentData.nextSibling;
    }
    size = constraints.constrain(
      vertical ? Size(cross, main) : Size(main, cross),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final boxes = _collectChildren();
    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      final childParentData = box.parentData! as _JointedParentData;
      final vertices = [
        Offset.zero,
        Offset(box.size.width, 0),
        Offset(box.size.width, box.size.height),
        Offset(0, box.size.height),
      ];
      final selected = _selectedFlags[i];
      context.canvas
        ..save()
        ..translate(
          offset.dx + childParentData.offset.dx,
          offset.dy + childParentData.offset.dy,
        );
      MonochromeBoxPainter(
        vertices: vertices,
        thicknessBase: _fixedThicknessBase,
        fillColor: selected ? GekigaColors.onPanel : GekigaColors.panel,
        seed: _seeds[i],
      ).paint(context.canvas, box.size);
      context.canvas.restore();
    }
    for (final box in boxes) {
      final childParentData = box.parentData! as _JointedParentData;
      context.paintChild(box, offset + childParentData.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;
}
