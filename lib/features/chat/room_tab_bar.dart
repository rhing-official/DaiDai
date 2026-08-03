import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
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

  void _handleSlideUpdate(Offset globalPosition) {
    for (final room in widget.rooms) {
      final rect = _rectFor(room.roomId);
      if (rect == null || !rect.contains(globalPosition)) continue;
      if (room.roomId != widget.selectedRoomId) {
        widget.onSelectRoom(room);
      }
      return;
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

    Widget roomList = ListView.separated(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      itemCount: widget.rooms.length,
      separatorBuilder: (_, _) => VerticalDivider(width: 1, color: borderColor),
      itemBuilder: (context, index) {
        final room = widget.rooms[index];
        final selected = room.roomId == widget.selectedRoomId;
        return KeyedSubtree(
          key: _keyFor(room.roomId),
          child: cell(
            selected: selected,
            onTap: () => widget.onSelectRoom(room),
            child: Text(
              '#${room.name}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foregroundColor,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );

    // 全セルが収まりきっている間だけ、メニューチップ（`_NavChip`）と同じ
    // 「指でなぞった先のタブへその場で切り替える」操作を有効にする
    // （メニューチップと異なり、なぞっている間セルを浮き上がらせる演出は
    // 付けない）。
    if (_canSlideSwitch) {
      roomList = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (details) =>
            _handleSlideUpdate(details.globalPosition),
        onHorizontalDragUpdate: (details) =>
            _handleSlideUpdate(details.globalPosition),
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
