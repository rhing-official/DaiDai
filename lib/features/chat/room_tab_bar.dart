import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/glass/glass_surface.dart';
import 'room_list_pane.dart' show RoomListEntry, promptForRoomName;

/// 狭い画面（縦表示）のチャット画面のAppBar下部に表示する、寄合の一覧タブバー
/// （2026-08-03追加、2026-09-07に複数行折り返し対応）。広い画面のサイドバー
/// （`RoomListPane`）と同じ役割を、AppBar直下に収まる形で提供する。単一モードの
/// 会話（`roomsEnabled == false`）では呼び出し側がそもそもこのウィジェットを
/// 使わない。削除・改名はこのバーからは行わず、開いている寄合のハンバーガー
/// メニュー（「寄合を削除」等）から行う（`RoomListPane`と同じ方針）。
/// タップした寄合への切り替えは呼び出し側が`pushReplacement`で画面自体を
/// 差し替えることで行う（`DmChatPane`/`GroupChatPane`参照。メッセージ一覧の
/// 購読・入力欄の状態などを寄合ごとにまっさらな状態へ戻すため）。
///
/// 寄合が増えて1行に収まらなくなった場合、横スクロールではなく複数行へ
/// 折り返す（ブラウザのタブのように、ユーザー選択の「多段タブ」方式）。
/// 折り返し後の行数は最大[_maxVisibleRows]行までバーの高さを伸ばし、それを
/// 超える分は固定高さの中に収める（寄合数が際限なく増えてもヘッダーが
/// 無限に伸びないようにするため）。バー自体は直接のスクロール操作には
/// 反応せず（2026-09-11変更）、寄合の選択操作（[_RoomTabBarState
/// ._handleSlideHover]、指を置いた寄合をなぞって選ぶ、横方向に加え縦方向にも
/// 対応）中に指が上端/下端の縁に達すると自動でスクロールする形で、隠れた行・
/// 「＋」ボタンへの到達手段を統合している。
///
/// `preferredSize`（`PreferredSizeWidget`のgetter、`BuildContext`を持たない）
/// で折り返し後の行数を知るには利用可能幅が要るが、この値は呼び出し元
/// （`chat_panes.dart`、`BuildContext`を持つ）から[maxWidth]・[textScaler]と
/// してコンストラクタ経由で受け取る。`preferredSize`と`build()`の両方が
/// 同じ入力から[_chunkIntoRows]を呼ぶため、高さと実際の行数は必ず一致する。
class RoomTabBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  const RoomTabBar({
    required this.rooms,
    required this.selectedRoomId,
    required this.onSelectRoom,
    required this.maxWidth,
    required this.isGekiga,
    this.textScaler = TextScaler.noScaling,
    this.onCreateRoom,
    super.key,
  });

  final List<RoomListEntry> rooms;
  final String selectedRoomId;
  final void Function(RoomListEntry room) onSelectRoom;

  /// nullなら追加セル自体を出さない（`RoomListPane.onCreateRoom`と同じく、
  /// 権限が無いメンバーには呼び出し側がnullを渡す）。
  final Future<void> Function(String name)? onCreateRoom;

  /// バーが使える横幅（呼び出し元の`MediaQuery.sizeOf(context).width`相当）。
  /// 行の折り返し判定にのみ使う。
  final double maxWidth;

  /// アクセシビリティ設定等によるテキスト拡大率（呼び出し元の
  /// `MediaQuery.textScalerOf(context)`）。折り返し判定の幅測定に使う。
  final TextScaler textScaler;

  /// 呼び出し元の`ref.watch(appUiStyleProvider) == AppUiStyle.gekiga`
  /// （2026-09-08追加）。`preferredSize`は`BuildContext`を持てないため、
  /// [maxWidth]・[textScaler]と同様にコンストラクタ経由で受け取る。劇画は
  /// タブ間隔が[GekigaJointedTileList.gap]（8px）とフラット/ガラスの
  /// [_dividerWidth]（1px）で異なり、`_chunkIntoRows`の折り返し判定を
  /// スタイルごとの実際の間隔に合わせる必要があるため。
  final bool isGekiga;

  static const double _height = 44;
  static const int _maxVisibleRows = 2;
  static const double _cellHPad = 14;
  static const double _cellMinWidth = 64;
  static const double _dividerWidth = 1;

  /// 折り返し判定専用の測定スタイル（実際の描画には使わない）。選択中セルの
  /// 太字より確実に広めに出るサイズ・太さにすることで、測定結果が実際の
  /// 描画幅を下回らないようにする（万一のずれで行が実際にはみ出すことを防ぐ、
  /// 安全マージン）。
  static const _measureStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.bold,
  );

  static double _itemWidth(RoomListEntry? room, TextScaler textScaler) {
    if (room == null) return _cellMinWidth;
    final painter = TextPainter(
      text: TextSpan(text: '#${room.name}', style: _measureStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    return math.max(_cellMinWidth, painter.width + _cellHPad * 2);
  }

  /// [rooms]（＋[hasAddCell]なら末尾に「＋」追加セル、`null`で表す）を、
  /// [maxWidth]に収まるよう貪欲法で複数行に分ける。1件だけで[maxWidth]を
  /// 超える長い名前も、分割・削除せずその行に単独で置く（実際の描画側の
  /// セルにも`maxWidth`制約と`Text`の省略表示を持たせて安全策にする）。
  /// `preferredSize`・`build()`の両方がこの関数を同じ引数で呼ぶことで、
  /// バーの高さと実際の行数を常に一致させる。
  ///
  /// [itemGap]はタブ間に実際に空く間隔（劇画は[GekigaJointedTileList.gap]
  /// ＝8px、フラット/ガラスは[_dividerWidth]＝1px）。以前はここが常に
  /// `_dividerWidth`決め打ちで、劇画の実際の間隔（8px）より狭く見積もって
  /// いたため、タブ数が多いと1行に収まりきらない数を「収まる」と誤判定して
  /// いた（2026-09-08修正）。
  static List<List<RoomListEntry?>> _chunkIntoRows({
    required List<RoomListEntry> rooms,
    required bool hasAddCell,
    required double maxWidth,
    required TextScaler textScaler,
    required double itemGap,
  }) {
    final items = <RoomListEntry?>[...rooms, if (hasAddCell) null];
    final rows = <List<RoomListEntry?>>[[]];
    var currentWidth = 0.0;
    for (final item in items) {
      final bareWidth = _itemWidth(item, textScaler);
      final isFirstInRow = rows.last.isEmpty;
      final addedWidth = isFirstInRow ? bareWidth : bareWidth + itemGap;
      if (!isFirstInRow && currentWidth + addedWidth > maxWidth) {
        rows.add([item]);
        currentWidth = bareWidth;
      } else {
        rows.last.add(item);
        currentWidth += addedWidth;
      }
    }
    return rows;
  }

  double get _itemGap => isGekiga ? GekigaJointedTileList.gap : _dividerWidth;

  @override
  Size get preferredSize {
    final rows = _chunkIntoRows(
      rooms: rooms,
      hasAddCell: onCreateRoom != null,
      maxWidth: maxWidth,
      textScaler: textScaler,
      itemGap: _itemGap,
    );
    final visibleRows = rows.length.clamp(1, _maxVisibleRows);
    // 行間の区切り（`isGekiga`はSizedBox(height:8)、それ以外はDivider(height:1)、
    // `build()`参照）の分を含めないと、劇画UIで2行目が実際のコンテンツ高さより
    // 低いこの`Size`からはみ出し途切れて見える不具合があった（2026-09-11修正）。
    return Size.fromHeight(
      visibleRows * _height + (visibleRows - 1) * _itemGap,
    );
  }

  @override
  ConsumerState<RoomTabBar> createState() => _RoomTabBarState();
}

class _RoomTabBarState extends ConsumerState<RoomTabBar> {
  final _verticalScrollController = ScrollController();

  /// 表示領域（`totalHeight`分の`SizedBox`）自体の実座標を引くための
  /// `GlobalKey`（2026-09-11追加）。縁でのオートスクロール（[_updateEdgeAutoScroll]
  /// 参照）が、指が上端/下端のどちら寄りかを判定するために使う。
  final _viewportKey = GlobalKey();

  /// セルごとのRenderBoxを引くための`GlobalKey`（roomId単位でキャッシュ）。
  /// 指でなぞっている間、どのセルの上に指があるかを実座標で判定するために
  /// 使う（`home_screen.dart`の`_NavChip`ドラッグ選択と同じ手法）。
  final Map<String, GlobalKey> _cellKeys = {};

  GlobalKey _keyFor(String roomId) =>
      _cellKeys.putIfAbsent(roomId, GlobalKey.new);

  /// ドラッグ中に指が乗っている寄合（未確定）。`pushReplacement`は指を
  /// 離した時に1回だけ行い、ドラッグ中はこの値でハイライトだけ追従させる
  /// （2026-08-10変更、詳細は[_handleSlideHover]参照）。
  String? _dragHoverRoomId;

  /// 縁でのオートスクロール中、次のtickでもハイライト判定をやり直すために
  /// 直近の指のグローバル座標を保持する（2026-09-11追加）。指が止まっていても
  /// スクロールで寄合の位置自体が動くため、指の移動イベント無しでも
  /// ハイライトを追従させる必要がある（[_autoScrollTimer]参照）。
  Offset? _lastDragGlobalPosition;

  /// 縁でのオートスクロールが動作中の方向（-1=上端方向／1=下端方向、
  /// nullなら停止中）。方向が変わった時だけタイマーを張り替える
  /// （2026-09-11追加）。
  double? _autoScrollDirection;
  Timer? _autoScrollTimer;

  static const _autoScrollEdgeThreshold = 32.0;
  static const _autoScrollStepPerTick = 6.0;
  static const _autoScrollTickInterval = Duration(milliseconds: 16);

  String get _effectiveSelectedRoomId =>
      _dragHoverRoomId ?? widget.selectedRoomId;

  Rect? _rectFor(String roomId) {
    final box = _cellKeys[roomId]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Rect? get _viewportRect {
    final box = _viewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// 劇画スタイル用のタブセル。塗り・枠は`GekigaJointedTileList`（呼び出し元）
  /// が`MonochromeBoxPainter`でまとめて描くため、ここでは中身
  /// （選択中=黒文字/未選択=白文字のテキスト）のみを組み立てる
  /// （2026-08-06追加）。
  Widget _gekigaCell(RoomListEntry room) {
    final selected = room.roomId == _effectiveSelectedRoomId;
    final fg = selected ? GekigaColors.panel : GekigaColors.onPanel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelectRoom(room),
        child: Container(
          // `maxWidth`は行全体の幅ではなく、`_chunkIntoRows`がこのセル分
          // として見積もった幅そのものにする（2026-09-08修正）。以前は
          // バー全体の`widget.maxWidth`を上限にしていたため、見積り用の
          // 固定スタイル（`_measureStyle`）と実際のアンビエントな文字
          // スタイルがずれた場合に実際の描画幅が見積りを超えても何も
          // 防げず、行の合計幅が`maxWidth`を超えて隣接する「＋」ボタンに
          // めり込む不具合があった。
          constraints: BoxConstraints(
            minWidth: RoomTabBar._cellMinWidth,
            maxWidth: RoomTabBar._itemWidth(room, widget.textScaler),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          alignment: Alignment.center,
          child: Text(
            '#${room.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  /// ドラッグ中、逐次呼ぶ（横方向・縦方向どちらのStart・Updateからも、
  /// 2026-09-11に縦方向を追加）。以前はここで即座に`widget.onSelectRoom`
  /// （実際の画面遷移）を呼んでいたが、寄合の切り替えは`pushReplacement`で
  /// `RoomTabBar`自身を含む画面全体を作り直すため、指を一時停止させて遷移
  /// アニメーションが完了すると、ここまでドラッグを検出していたジェスチャー
  /// 自体が消滅し、以降指を動かしても次のチップへ切り替わらなくなる不具合
  /// があった（2026-08-10発覚）。実際の遷移は指を離した時点で一度だけ行い
  /// （[_commitDragSelection]）、ドラッグ中はハイライトの追従のみに留めることで
  /// この問題を回避する。各セルの実座標（`GlobalKey`経由）による2D判定のため、
  /// 複数行に折り返っても行をまたいだ判定ができる（縦方向にドラッグして
  /// 行を移動する場合も同じ判定で追従する）。
  void _handleSlideHover(Offset globalPosition) {
    _lastDragGlobalPosition = globalPosition;
    _updateHoverHighlight(globalPosition);
    _updateEdgeAutoScroll(globalPosition);
  }

  void _updateHoverHighlight(Offset globalPosition) {
    for (final room in widget.rooms) {
      final rect = _rectFor(room.roomId);
      if (rect == null || !rect.contains(globalPosition)) continue;
      if (room.roomId != _effectiveSelectedRoomId) {
        setState(() => _dragHoverRoomId = room.roomId);
      }
      return;
    }
  }

  /// 指が表示領域の上端/下端の縁（[_autoScrollEdgeThreshold]px以内）に
  /// 達していて、かつその方向にまだスクロールできる内容があれば、
  /// [_verticalScrollController]を少しずつ動かし続ける（2026-09-11追加）。
  /// バー自体は[NeverScrollableScrollPhysics]で直接のスクロール操作には
  /// 反応しないが、2行を超える寄合・「＋」ボタンには、この「縁に指を置いた
  /// ままにすると自動でスクロールする」操作だけで到達できるようにする
  /// （2行目の寄合の上から指を下へ動かし続けると隠れた3行目以降へ追従する）。
  void _updateEdgeAutoScroll(Offset globalPosition) {
    final viewport = _viewportRect;
    if (viewport == null ||
        !_verticalScrollController.hasClients ||
        !_verticalScrollController.position.hasContentDimensions) {
      _stopAutoScroll();
      return;
    }
    final localY = globalPosition.dy - viewport.top;
    final position = _verticalScrollController.position;
    double? direction;
    if (localY > viewport.height - _autoScrollEdgeThreshold &&
        position.pixels < position.maxScrollExtent) {
      direction = 1;
    } else if (localY < _autoScrollEdgeThreshold &&
        position.pixels > position.minScrollExtent) {
      direction = -1;
    }
    if (direction == null) {
      _stopAutoScroll();
      return;
    }
    if (_autoScrollDirection == direction) return;
    _stopAutoScroll();
    _autoScrollDirection = direction;
    _autoScrollTimer = Timer.periodic(_autoScrollTickInterval, (_) {
      if (!_verticalScrollController.hasClients) {
        _stopAutoScroll();
        return;
      }
      final position = _verticalScrollController.position;
      final next = (position.pixels + direction! * _autoScrollStepPerTick)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (next == position.pixels) {
        _stopAutoScroll();
        return;
      }
      _verticalScrollController.jumpTo(next);
      final pos = _lastDragGlobalPosition;
      if (pos != null) _updateHoverHighlight(pos);
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDirection = null;
  }

  /// 指を離した（またはドラッグがキャンセルされた）時に呼ぶ。ドラッグ中に
  /// ハイライトが乗っていた寄合が実際の選択中と異なれば、ここで初めて
  /// `widget.onSelectRoom`（画面遷移）を1回だけ行う。
  void _commitDragSelection() {
    _stopAutoScroll();
    _lastDragGlobalPosition = null;
    final hoverId = _dragHoverRoomId;
    if (hoverId == null) return;
    setState(() => _dragHoverRoomId = null);
    if (hoverId == widget.selectedRoomId) return;
    for (final room in widget.rooms) {
      if (room.roomId == hoverId) {
        widget.onSelectRoom(room);
        return;
      }
    }
  }

  Future<void> _createRoom(
    BuildContext context,
    Strings strings,
    Vocabulary vocab,
    bool isGekiga,
    bool isGlass,
  ) async {
    final name = await promptForRoomName(
      context,
      strings,
      vocab,
      isGekiga,
      isGlass,
    );
    if (name == null || name.isEmpty) return;
    await widget.onCreateRoom?.call(name);
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    // AppBar.bottomとして使われる前提のため、AppBar自身のIconTheme（劇画
    // スタイルなら白、それ以外は既定色）をそのまま引き継ぐ。
    final foregroundColor =
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    final borderColor = foregroundColor.withValues(alpha: 0.35);
    final highlightColor = foregroundColor.withValues(alpha: 0.15);

    final rows = RoomTabBar._chunkIntoRows(
      rooms: widget.rooms,
      hasAddCell: widget.onCreateRoom != null,
      maxWidth: widget.maxWidth,
      textScaler: widget.textScaler,
      itemGap: widget._itemGap,
    );
    final visibleRows = rows.length.clamp(1, RoomTabBar._maxVisibleRows);
    // [RoomTabBar.preferredSize]と同じ理由（2026-09-11修正）。
    final totalHeight =
        visibleRows * RoomTabBar._height + (visibleRows - 1) * widget._itemGap;

    // フラット/ガラス共通のセル。`room`がnullなら末尾の「＋」追加セル。
    Widget flatCell(RoomListEntry? room) {
      final isAdd = room == null;
      final selected = !isAdd && room.roomId == _effectiveSelectedRoomId;
      // `maxWidth`は行全体の幅ではなく、`_chunkIntoRows`がこのセル分として
      // 見積もった幅そのものにする（2026-09-08修正、`_gekigaCell`と同じ
      // 理由）。「＋」セルは名前を持たないため見積り不要、固定の最小幅で足りる。
      final cellMaxWidth = isAdd
          ? RoomTabBar._cellMinWidth
          : RoomTabBar._itemWidth(room, widget.textScaler);
      final child = InkWell(
        onTap: isAdd
            ? () => _createRoom(context, strings, vocab, false, isGlass)
            : () => widget.onSelectRoom(room),
        child: Container(
          constraints: BoxConstraints(
            minWidth: RoomTabBar._cellMinWidth,
            maxWidth: cellMaxWidth,
          ),
          padding: const EdgeInsets.symmetric(horizontal: RoomTabBar._cellHPad),
          alignment: Alignment.center,
          color: selected ? highlightColor : null,
          child: isAdd
              ? Icon(Icons.add, size: 20, color: foregroundColor)
              : Text(
                  '#${room.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
        ),
      );
      return isAdd
          ? child
          : KeyedSubtree(key: _keyFor(room.roomId), child: child);
    }

    Widget buildRow(List<RoomListEntry?> row) {
      // 「＋」は`_chunkIntoRows`の構成上、必ず全体の最後の要素＝最後の行の
      // 末尾にしか現れない。フラット/ガラス・劇画のいずれも、寄合chip群を
      // `Flexible`で包み「＋」をその外（`VerticalDivider`を挟んだ固定スロット）
      // に置くことで、行のRowが画面幅いっぱいに広がる分だけ「＋」が常にバー
      // 右端（画面端）に固定される（2026-09-11修正、以前はフラット/ガラス側
      // だけ`Flexible`が無く、「＋」がchip数に応じて位置が動いていた）。
      final realRooms = row.whereType<RoomListEntry>().toList();
      final hasAdd = row.isNotEmpty && row.last == null;
      if (isGekiga) {
        // 「＋」は劇画でも他の一覧と共通の`GekigaIconBadge`を使う、
        // ジョイント枠の外の独立したセルのまま維持する（追加セルの並びが
        // 変わっても既存の見た目を保つため）。
        return SizedBox(
          height: RoomTabBar._height,
          child: Row(
            children: [
              Flexible(
                child: Center(
                  child: GekigaJointedTileList(
                    axis: Axis.horizontal,
                    seeds: [for (final room in realRooms) room.roomId.hashCode],
                    selectedFlags: [
                      for (final room in realRooms)
                        room.roomId == _effectiveSelectedRoomId,
                    ],
                    children: [
                      for (final room in realRooms)
                        KeyedSubtree(
                          key: _keyFor(room.roomId),
                          child: _gekigaCell(room),
                        ),
                    ],
                  ),
                ),
              ),
              if (hasAdd) ...[
                VerticalDivider(width: 1, color: borderColor),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () =>
                        _createRoom(context, strings, vocab, true, false),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: RoomTabBar._cellMinWidth,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      child: const GekigaIconBadge(icon: Icons.add, size: 28),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }
      return SizedBox(
        height: RoomTabBar._height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              // 万一chip群の合計幅が見積りを超えても、はみ出しが「＋」ボタン
              // 側に影響しないようクリップする（2026-09-08追加の安全策、
              // 劇画側のクリップと同じ狙い。2026-09-11、「＋」を含む行全体
              // ではなくchip群側だけをクリップする構成に変更）。
              child: ClipRect(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < realRooms.length; i++) ...[
                      if (i > 0) VerticalDivider(width: 1, color: borderColor),
                      flatCell(realRooms[i]),
                    ],
                  ],
                ),
              ),
            ),
            if (hasAdd) ...[
              VerticalDivider(width: 1, color: borderColor),
              flatCell(null),
            ],
          ],
        ),
      );
    }

    Widget content = SizedBox(
      key: _viewportKey,
      height: totalHeight,
      child: SingleChildScrollView(
        controller: _verticalScrollController,
        // 直接のスクロール操作には反応しない（2026-09-11変更）。2行を超える
        // 寄合・「＋」ボタンには、[_updateEdgeAutoScroll]による「縁に指を
        // 置いたままにすると自動でスクロールする」操作だけで到達させる方針
        // にしたため、独立したスクロールジェスチャーは不要になった
        // （`_verticalScrollController`自体は残し、そちらからの
        // `jumpTo`/`animateTo`でのみ動かす）。
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              // 行間の区切り幅は`_itemGap`（本来は横方向のセル間隔用）と同じ値
              // （劇画8px／それ以外1px）を流用する。`totalHeight`・
              // `preferredSize`の計算にもこの値を使っており、ずれると劇画UIで
              // 2行目が途切れる不具合になる（2026-09-11修正）。
              if (i > 0)
                isGekiga
                    ? const SizedBox(height: 8)
                    : Divider(height: 1, color: borderColor),
              buildRow(rows[i]),
            ],
          ],
        ),
      ),
    );

    // 横方向のドラッグ（既存）・縦方向のドラッグ（2026-09-11追加）の両方で
    // 寄合の選択が追従する。縦方向は複数行に折り返った時に行をまたいで
    // 選択するための操作で、指が表示領域の縁に達すると[_updateEdgeAutoScroll]
    // が自動でスクロールし、2行を超える寄合・「＋」ボタンにも到達できる。
    content = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) =>
          _handleSlideHover(details.globalPosition),
      onHorizontalDragUpdate: (details) =>
          _handleSlideHover(details.globalPosition),
      onHorizontalDragEnd: (_) => _commitDragSelection(),
      onHorizontalDragCancel: _commitDragSelection,
      onVerticalDragStart: (details) =>
          _handleSlideHover(details.globalPosition),
      onVerticalDragUpdate: (details) =>
          _handleSlideHover(details.globalPosition),
      onVerticalDragEnd: (_) => _commitDragSelection(),
      onVerticalDragCancel: _commitDragSelection,
      child: content,
    );

    if (isGlass) {
      return GlassSurface(
        variant: GlassVariant.chrome,
        borderRadius: BorderRadius.zero,
        enableEdgeStroke: false,
        child: SizedBox(height: totalHeight, child: content),
      );
    }

    return Container(
      height: totalHeight,
      // 2026-08-30、チャット画面のScaffold.extendBodyBehindAppBarが全
      // スタイル共通でtrueになったのに合わせ、明示的に不透明背景を指定
      // する（以前はextendBodyBehindAppBar=falseだったため指定が無くても
      // 不透明に見えていた。ここは寄合切り替えタブのため、今回の「上部の
      // アイコン行の背景を消す」変更の対象外として現状の見た目を保つ）。
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: content,
    );
  }
}
