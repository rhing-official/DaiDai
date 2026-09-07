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
/// 超える分は固定高さの中で縦スクロールして到達できるようにする（寄合数が
/// 際限なく増えてもヘッダーが無限に伸びないようにするため）。
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
  static List<List<RoomListEntry?>> _chunkIntoRows({
    required List<RoomListEntry> rooms,
    required bool hasAddCell,
    required double maxWidth,
    required TextScaler textScaler,
  }) {
    final items = <RoomListEntry?>[...rooms, if (hasAddCell) null];
    final rows = <List<RoomListEntry?>>[[]];
    var currentWidth = 0.0;
    for (final item in items) {
      final bareWidth = _itemWidth(item, textScaler);
      final isFirstInRow = rows.last.isEmpty;
      final addedWidth = isFirstInRow ? bareWidth : bareWidth + _dividerWidth;
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

  @override
  Size get preferredSize {
    final rows = _chunkIntoRows(
      rooms: rooms,
      hasAddCell: onCreateRoom != null,
      maxWidth: maxWidth,
      textScaler: textScaler,
    );
    final visibleRows = rows.length.clamp(1, _maxVisibleRows);
    return Size.fromHeight(visibleRows * _height);
  }

  @override
  ConsumerState<RoomTabBar> createState() => _RoomTabBarState();
}

class _RoomTabBarState extends ConsumerState<RoomTabBar> {
  final _verticalScrollController = ScrollController();

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

  String get _effectiveSelectedRoomId =>
      _dragHoverRoomId ?? widget.selectedRoomId;

  Rect? _rectFor(String roomId) {
    final box = _cellKeys[roomId]?.currentContext?.findRenderObject();
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
          constraints: BoxConstraints(
            minWidth: RoomTabBar._cellMinWidth,
            maxWidth: widget.maxWidth,
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

  /// ドラッグ中、逐次呼ぶ（Start・Updateの両方から）。以前はここで即座に
  /// `widget.onSelectRoom`（実際の画面遷移）を呼んでいたが、寄合の切り替えは
  /// `pushReplacement`で`RoomTabBar`自身を含む画面全体を作り直すため、指を
  /// 一時停止させて遷移アニメーションが完了すると、ここまでドラッグを検出
  /// していたジェスチャー自体が消滅し、以降指を動かしても次のチップへ切り
  /// 替わらなくなる不具合があった（2026-08-10発覚）。実際の遷移は指を離した
  /// 時点で一度だけ行い（[_commitDragSelection]）、ドラッグ中はハイライトの
  /// 追従のみに留めることでこの問題を回避する。各セルの実座標（`GlobalKey`
  /// 経由）による2D判定のため、複数行に折り返っても行をまたいだ誤判定は
  /// 起きない（横方向にドラッグしている間はY座標が同じ行の帯内に留まる）。
  /// 行の右端を超えてドラッグしても次の行へは自動で移らない（1行だった頃の
  /// 「最後のセルを超えると追従が止まる」動作と同じ）。
  void _handleSlideHover(Offset globalPosition) {
    for (final room in widget.rooms) {
      final rect = _rectFor(room.roomId);
      if (rect == null || !rect.contains(globalPosition)) continue;
      if (room.roomId != _effectiveSelectedRoomId) {
        setState(() => _dragHoverRoomId = room.roomId);
      }
      return;
    }
  }

  /// 指を離した（またはドラッグがキャンセルされた）時に呼ぶ。ドラッグ中に
  /// ハイライトが乗っていた寄合が実際の選択中と異なれば、ここで初めて
  /// `widget.onSelectRoom`（画面遷移）を1回だけ行う。
  void _commitDragSelection() {
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
  ) async {
    final name = await promptForRoomName(context, strings, vocab, isGekiga);
    if (name == null || name.isEmpty) return;
    await widget.onCreateRoom?.call(name);
  }

  @override
  void dispose() {
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
    );
    final visibleRows = rows.length.clamp(1, RoomTabBar._maxVisibleRows);
    final totalHeight = visibleRows * RoomTabBar._height;

    // フラット/ガラス共通のセル。`room`がnullなら末尾の「＋」追加セル。
    Widget flatCell(RoomListEntry? room) {
      final isAdd = room == null;
      final selected = !isAdd && room.roomId == _effectiveSelectedRoomId;
      final child = InkWell(
        onTap: isAdd
            ? () => _createRoom(context, strings, vocab, false)
            : () => widget.onSelectRoom(room),
        child: Container(
          constraints: BoxConstraints(
            minWidth: RoomTabBar._cellMinWidth,
            maxWidth: widget.maxWidth,
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
      if (isGekiga) {
        // 「＋」は劇画でも他の一覧と共通の`GekigaIconBadge`を使う、
        // ジョイント枠の外の独立したセルのまま維持する（追加セルの並びが
        // 変わっても既存の見た目を保つため）。「＋」は`_chunkIntoRows`の
        // 構成上、必ず全体の最後の要素＝最後の行の末尾にしか現れない。
        final realRooms = row.whereType<RoomListEntry>().toList();
        final hasAdd = row.isNotEmpty && row.last == null;
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
                    onTap: () => _createRoom(context, strings, vocab, true),
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
            for (var i = 0; i < row.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, color: borderColor),
              flatCell(row[i]),
            ],
          ],
        ),
      );
    }

    Widget content = SizedBox(
      height: totalHeight,
      child: SingleChildScrollView(
        controller: _verticalScrollController,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
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

    // 複数行に折り返っても、バー内で横スクロールする箇所自体が無くなった
    // （各行は`maxWidth`に収まるよう構成されるため）ため、以前あった
    // 「横スクロールが不要な時だけ有効化」というガードは不要になり、常時
    // 有効にする（2026-09-07変更）。
    content = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) =>
          _handleSlideHover(details.globalPosition),
      onHorizontalDragUpdate: (details) =>
          _handleSlideHover(details.globalPosition),
      onHorizontalDragEnd: (_) => _commitDragSelection(),
      onHorizontalDragCancel: _commitDragSelection,
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
