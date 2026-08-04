import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/gekiga/gekiga_shapes.dart';

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
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[
          IconTheme.merge(
            data: IconThemeData(color: fg),
            child: leading,
          ),
          const SizedBox(width: 16),
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
          const SizedBox(width: 12),
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
/// のように要素数1のリストとして渡し、[_GekigaJointedList]の接合枠描画
/// （要素が1つなら隣接共有ロジックは発火しない）をそのまま「単体の
/// ジグザグ枠ボタン」として再利用する（2026-08-04新規、身だしなみの
/// 保存/削除/追加ボタン向け）。[selected]は選択状態ではなく、他の劇画UI
/// 要素と同じ「選択中=白地黒文字／未選択=黒地白文字」のルールをボタンの
/// 強弱表現に転用したもの（true＝主要操作、false＝副次的操作）。
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

/// [GekigaJointedTileList]・[GekigaJointedPair]で使う、隙間なく並べた
/// 箱同士の接する辺を1本の折れ線として共有する実装本体（2026-08-04追加）。
///
/// 各箱は`_GekigaPanelBoxPainter`と同じ手描き風ジグザグ矩形を描くが、
/// 隣接する箱と接する辺（[Axis.vertical]なら上辺/下辺、[Axis.horizontal]
/// なら左辺/右辺）だけは、隣の箱と**同じ`seed`・同じ座標**で
/// [jitteredEdgePoints]を呼ぶことでピクセル単位で同一の折れ線にする
/// （箱を「透明な板」として左上（または上）基準で積むと、隣接する箱の
/// 接する辺は`(0, 局所y)`または`(局所x, 0)`という自分のローカル座標系で
/// 見ても常にグローバル座標が一致するため、同じseed・同じ交差軸の範囲で
/// 生成すれば自動的に同じ折れ線になる）。
///
/// 箱の交差軸方向の長さ（可変幅リストなら幅、[GekigaJointedPair]なら
/// 高さ）が隣同士で異なる場合は、重なる範囲（`min`）だけ共有し、はみ出す
/// 範囲は自分自身の`seed`で独立にジグザグを続ける（短い方に合わせて
/// 伸ばさない）。
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

  // 隣接する箱同士がほぼ同じ幅になりやすく（短い名前が並ぶ等）、共有辺が
  // 大半を占めてしまうと箱ごとの個性が出にくいとの指摘を受け、独立辺
  // （左右辺）のジグザグをやや強めた（2026-08-04、2.4→3.0・segments 5→6）。
  static const double _jitter = 3.0;
  static const int _segmentsPerEdge = 6;
  static const double _strokeWidth = 2.6;

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
    var child = firstChild;
    while (child != null) {
      child.layout(loose, parentUsesSize: true);
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

  double _crossSizeOf(Size s) => _axis == Axis.vertical ? s.width : s.height;

  @override
  void paint(PaintingContext context, Offset offset) {
    final boxes = _collectChildren();
    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      final childParentData = box.parentData! as _JointedParentData;
      final path = _boxPath(
        size: box.size,
        ownSeed: _seeds[i],
        joinBeforeSeed: i > 0 ? Object.hash(_seeds[i - 1], _seeds[i]) : null,
        joinBeforeCross: i > 0 ? _crossSizeOf(boxes[i - 1].size) : null,
        joinAfterSeed: i < boxes.length - 1
            ? Object.hash(_seeds[i], _seeds[i + 1])
            : null,
        joinAfterCross: i < boxes.length - 1
            ? _crossSizeOf(boxes[i + 1].size)
            : null,
      );
      final selected = _selectedFlags[i];
      final fillColor = selected ? GekigaColors.onPanel : GekigaColors.panel;
      final strokeColor = selected ? GekigaColors.panel : GekigaColors.onPanel;
      context.canvas
        ..save()
        ..translate(
          offset.dx + childParentData.offset.dx,
          offset.dy + childParentData.offset.dy,
        )
        ..drawPath(path, Paint()..color = fillColor)
        ..drawPath(
          path,
          Paint()
            ..color = strokeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = _strokeWidth
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round,
        )
        ..restore();
    }
    for (final box in boxes) {
      final childParentData = box.parentData! as _JointedParentData;
      context.paintChild(box, offset + childParentData.offset);
    }
  }

  /// この箱1つ分の、接合込みの手描き風ジグザグ矩形のPathを作る。
  Path _boxPath({
    required Size size,
    required int ownSeed,
    int? joinBeforeSeed,
    double? joinBeforeCross,
    int? joinAfterSeed,
    double? joinAfterCross,
  }) {
    final vertical = _axis == Axis.vertical;
    final w = size.width;
    final h = size.height;
    final crossLength = vertical ? w : h;

    // 開始側の辺（vertical: 上辺／horizontal: 左辺）と終了側の辺
    // （vertical: 下辺／horizontal: 右辺）。どちらも交差軸方向に
    // 0→crossLengthの向き（vertical: 左→右／horizontal: 上→下）で
    // 生成し、矩形の周を辿るときに必要な方だけ`.reversed`する。
    final startEdge = _crossEdgePoints(
      crossLength: crossLength,
      mainPos: 0,
      vertical: vertical,
      joinSeed: joinBeforeSeed,
      joinCross: joinBeforeCross,
      ownSeed: ownSeed ^ 0x51a7,
    );
    final endEdge = _crossEdgePoints(
      crossLength: crossLength,
      mainPos: vertical ? h : w,
      vertical: vertical,
      joinSeed: joinAfterSeed,
      joinCross: joinAfterCross,
      ownSeed: ownSeed ^ 0x2f91,
    );

    if (vertical) {
      final right = jitteredEdgePoints(
        Offset(w, 0),
        Offset(w, h),
        ownSeed ^ 0x3c61,
        jitter: _jitter,
        segments: _segmentsPerEdge,
      );
      final left = jitteredEdgePoints(
        Offset(0, h),
        Offset(0, 0),
        ownSeed ^ 0x7b2d,
        jitter: _jitter,
        segments: _segmentsPerEdge,
      );
      // 各辺の点列は必ず開始側の頂点から少し離れた位置（t=1/segments）から
      // 始まる（[jitteredEdgePoints]参照）。共有辺（上辺/下辺）は隣の箱と
      // 座標を合わせるため常に「交差軸0→crossLength」の向きで生成してから
      // 必要に応じて`.reversed`するが、この向き固定のせいで4辺を単純に
      // 連結すると、ちょうど左下の角で「下辺の終端側の頂点(t=1/segments、
      // 角から離れた点)」と「左辺の始端側の頂点(同じく角から離れた点)」が
      // 隣り合ってしまい、他の3つの角（少なくとも片方は角に近い点になる）
      // より明らかに大きい欠けが左下にだけ生じる不具合があった
      // （2026-08-04発覚・修正。数学的に、共有辺の向きを固定する制約上
      // 4辺のうち2辺は必ず組み合わせが噛み合わなくなるが、他の2箇所は
      // 「両方とも角に近い」で済むのに対し左下だけ「両方とも角から離れる」
      // 側になってしまうことが原因）。四隅の実座標を明示的に挟むことで、
      // どの角も最悪でも角のすぐそばで折れ線がつながるようにする。
      return pathFromPoints([
        Offset.zero, // 左上
        ...startEdge, // 上辺: 左→右
        Offset(w, 0), // 右上
        ...right, // 右辺: 上→下
        Offset(w, h), // 右下
        ...endEdge.reversed, // 下辺: 右→左
        Offset(0, h), // 左下
        ...left, // 左辺: 下→上
      ]);
    }
    final bottom = jitteredEdgePoints(
      Offset(0, h),
      Offset(w, h),
      ownSeed ^ 0x3c61,
      jitter: _jitter,
      segments: _segmentsPerEdge,
    );
    final top = jitteredEdgePoints(
      Offset(w, 0),
      Offset(0, 0),
      ownSeed ^ 0x7b2d,
      jitter: _jitter,
      segments: _segmentsPerEdge,
    );
    // 縦積み（vertical）と同じ理由で、四隅の実座標を明示的に挟む。
    return pathFromPoints([
      Offset.zero, // 左上
      ...startEdge, // 左辺: 上→下
      Offset(0, h), // 左下
      ...bottom, // 下辺: 左→右
      Offset(w, h), // 右下
      ...endEdge.reversed, // 右辺: 下→上
      Offset(w, 0), // 右上
      ...top, // 上辺: 右→左
    ]);
  }

  /// 交差軸方向に伸びる1辺（vertical: 上辺/下辺、horizontal: 左辺/右辺）の
  /// 点列。[joinSeed]が指定されていれば、隣の箱の交差軸長[joinCross]との
  /// 重なる範囲（`min(crossLength, joinCross)`）だけ[joinSeed]で隣と
  /// 同一の折れ線にし、はみ出す範囲（自分の方が長い場合のみ）は[ownSeed]
  /// で独立に継続する。[joinSeed]がnull（隣接する箱が無い辺）なら全長を
  /// [ownSeed]だけで描く。
  List<Offset> _crossEdgePoints({
    required double crossLength,
    required double mainPos,
    required bool vertical,
    required int? joinSeed,
    required double? joinCross,
    required int ownSeed,
  }) {
    Offset point(double crossPos) =>
        vertical ? Offset(crossPos, mainPos) : Offset(mainPos, crossPos);

    if (joinSeed == null || joinCross == null || joinCross <= 0) {
      return jitteredEdgePoints(
        point(0),
        point(crossLength),
        ownSeed,
        jitter: _jitter,
        segments: _segmentsPerEdge,
      );
    }
    final overlap = math.min(crossLength, joinCross);
    final jointPart = jitteredEdgePoints(
      point(0),
      point(overlap),
      joinSeed,
      jitter: _jitter,
      segments: _segmentsPerEdge,
    );
    if (overlap >= crossLength - 0.01) return jointPart;
    final ownPart = jitteredEdgePoints(
      point(overlap),
      point(crossLength),
      ownSeed,
      jitter: _jitter,
      segments: _segmentsPerEdge,
    );
    return [...jointPart, ...ownPart];
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
