import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../utils/text_truncate.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import 'room_list_pane.dart' show RoomListEntry, promptForRoomName;

/// 狭い画面（縦表示）のチャット画面のAppBar下部に表示する、寄合の横スクロール
/// タブバー（2026-08-03追加）。広い画面のサイドバー（`RoomListPane`）と同じ
/// 役割を、`AppBar.bottom`に収まる横並びのセルとして提供する。単一モードの
/// 会話（`roomsEnabled == false`）では呼び出し側がそもそもこのウィジェットを
/// 使わない。削除・改名はこのバーからは行わず、開いている寄合のハンバーガー
/// メニュー（「寄合を削除」等）から行う（`RoomListPane`と同じ方針）。
/// タップした寄合への切り替えは呼び出し側が`pushReplacement`で画面自体を
/// 差し替えることで行う（`DmChatPane`/`GroupChatPane`参照。メッセージ一覧の
/// 購読・入力欄の状態などを寄合ごとにまっさらな状態へ戻すため）。
class RoomTabBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  const RoomTabBar({
    required this.rooms,
    required this.selectedRoomId,
    required this.onSelectRoom,
    this.onCreateRoom,
    super.key,
  });

  final List<RoomListEntry> rooms;
  final String selectedRoomId;
  final void Function(RoomListEntry room) onSelectRoom;

  /// nullなら追加セル自体を出さない（`RoomListPane.onCreateRoom`と同じく、
  /// 権限が無いメンバーには呼び出し側がnullを渡す）。
  final Future<void> Function(String name)? onCreateRoom;

  static const double _height = 44;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  ConsumerState<RoomTabBar> createState() => _RoomTabBarState();
}

class _RoomTabBarState extends ConsumerState<RoomTabBar> {
  final _scrollController = ScrollController();

  /// セルごとのRenderBoxを引くための`GlobalKey`（roomId単位でキャッシュ）。
  /// 指でなぞっている間、どのセルの上に指があるかを実座標で判定するために
  /// 使う（`home_screen.dart`の`_NavChip`ドラッグ選択と同じ手法）。
  final Map<String, GlobalKey> _cellKeys = {};

  /// スライド切り替えを許可するか。タブが全部横幅に収まりきらず
  /// 横スクロールが必要な場合、ドラッグ操作をスライド切り替えに使ってしまうと
  /// 本来のスクロール操作ができなくなってしまうため、全セルが1画面に収まって
  /// いる（スクロール不要な）ときだけ有効にする（2026-08-03新規）。
  bool _canSlideSwitch = false;

  GlobalKey _keyFor(String roomId) =>
      _cellKeys.putIfAbsent(roomId, GlobalKey.new);

  /// ドラッグ中に指が乗っている寄合（未確定）。`pushReplacement`は指を
  /// 離した時に1回だけ行い、ドラッグ中はこの値でハイライトだけ追従させる
  /// （2026-08-10変更、詳細は[_handleSlideHover]参照）。
  String? _dragHoverRoomId;

  String get _effectiveSelectedRoomId =>
      _dragHoverRoomId ?? widget.selectedRoomId;

  void _scheduleSlideSwitchCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final canSlide = _scrollController.position.maxScrollExtent <= 0;
      if (canSlide != _canSlideSwitch) {
        setState(() => _canSlideSwitch = canSlide);
      }
    });
  }

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
          constraints: const BoxConstraints(minWidth: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          alignment: Alignment.center,
          child: Text(
            '#${truncateName(room.name, 6)}',
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
  /// 追従のみに留めることでこの問題を回避する。
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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    // AppBar.bottomとして使われる前提のため、AppBar自身のIconTheme（劇画
    // スタイルなら白、それ以外は既定色）をそのまま引き継ぐ。
    final foregroundColor =
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    final borderColor = foregroundColor.withValues(alpha: 0.35);
    final highlightColor = foregroundColor.withValues(alpha: 0.15);

    // 寄合の増減・画面幅変化のたびに、スクロールが不要かどうかを
    // 描画後に測り直す。
    _scheduleSlideSwitchCheck();

    Widget cell({
      required Widget child,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          color: selected ? highlightColor : null,
          child: child,
        ),
      );
    }

    // 劇画スタイルでは、他の一覧（RoomListPane・一対/広場カテゴリタブ）と
    // 同じ「モノクロボックス」意匠（黒外枠→白内枠→塗り色、選択中=白地黒文字・
    // 未選択=黒地白文字）を使う（2026-08-06追加）。`GekigaJointedTileList`は
    // 全子を即座に構築する`MultiChildRenderObjectWidget`のため、`ListView`の
    // ような遅延構築（virtualized）はできないが、寄合の個数は現実的に少数
    // のため問題にならない。`SingleChildScrollView`で自前の横スクロールに
    // 切り替える（`RoomListPane`の縦一覧と同じ非virtualizedパターン）。
    Widget roomList = isGekiga
        ? SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: GekigaJointedTileList(
              axis: Axis.horizontal,
              seeds: [for (final room in widget.rooms) room.roomId.hashCode],
              selectedFlags: [
                for (final room in widget.rooms)
                  room.roomId == _effectiveSelectedRoomId,
              ],
              children: [
                for (final room in widget.rooms)
                  KeyedSubtree(
                    key: _keyFor(room.roomId),
                    child: _gekigaCell(room),
                  ),
              ],
            ),
          )
        : ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: widget.rooms.length,
            separatorBuilder: (_, _) =>
                VerticalDivider(width: 1, color: borderColor),
            itemBuilder: (context, index) {
              final room = widget.rooms[index];
              final selected = room.roomId == _effectiveSelectedRoomId;
              return KeyedSubtree(
                key: _keyFor(room.roomId),
                child: cell(
                  selected: selected,
                  onTap: () => widget.onSelectRoom(room),
                  child: Text(
                    '#${truncateName(room.name, 6)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foregroundColor,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            },
          );

    // 全セルが収まりきっている間だけ、メニューチップ（`_NavChip`）と同じ
    // 「指でなぞった先のタブへハイライトが追従する」操作を有効にする
    // （メニューチップと異なり、なぞっている間セルを浮き上がらせる演出は
    // 付けない）。メニューチップはなぞった瞬間に即座にタブが切り替わるが、
    // 寄合の切り替えは`pushReplacement`で`RoomTabBar`自身を含む画面全体を
    // 作り直すため、同じ即時切り替えにすると一時停止でジェスチャーが
    // 途切れる不具合が起きる（[_handleSlideHover]参照）。実際の切り替えは
    // 指を離した時点で一度だけ行う。
    if (_canSlideSwitch) {
      roomList = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (details) =>
            _handleSlideHover(details.globalPosition),
        onHorizontalDragUpdate: (details) =>
            _handleSlideHover(details.globalPosition),
        onHorizontalDragEnd: (_) => _commitDragSelection(),
        onHorizontalDragCancel: _commitDragSelection,
        child: roomList,
      );
    }

    return Container(
      height: RoomTabBar._height,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Expanded(child: roomList),
          if (widget.onCreateRoom != null) ...[
            VerticalDivider(width: 1, color: borderColor),
            cell(
              selected: false,
              onTap: () => _createRoom(context, strings, vocab, isGekiga),
              child: isGekiga
                  ? const GekigaIconBadge(icon: Icons.add, size: 28)
                  : Icon(Icons.add, size: 20, color: foregroundColor),
            ),
          ],
        ],
      ),
    );
  }
}
