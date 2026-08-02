import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
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
class RoomTabBar extends ConsumerWidget implements PreferredSizeWidget {
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

  Future<void> _createRoom(
    BuildContext context,
    Strings strings,
    Vocabulary vocab,
  ) async {
    final name = await promptForRoomName(context, strings, vocab);
    if (name == null || name.isEmpty) return;
    await onCreateRoom?.call(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    // AppBar.bottomとして使われる前提のため、AppBar自身のIconTheme（劇画
    // スタイルなら白、それ以外は既定色）をそのまま引き継ぐ。
    final foregroundColor =
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    final borderColor = foregroundColor.withValues(alpha: 0.35);
    final highlightColor = foregroundColor.withValues(alpha: 0.15);

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

    return Container(
      height: _height,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: rooms.length,
              separatorBuilder: (_, _) =>
                  VerticalDivider(width: 1, color: borderColor),
              itemBuilder: (context, index) {
                final room = rooms[index];
                final selected = room.roomId == selectedRoomId;
                return cell(
                  selected: selected,
                  onTap: () => onSelectRoom(room),
                  child: Text(
                    '#${room.name}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foregroundColor,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
          if (onCreateRoom != null) ...[
            VerticalDivider(width: 1, color: borderColor),
            cell(
              selected: false,
              onTap: () => _createRoom(context, strings, vocab),
              child: Icon(Icons.add, size: 20, color: foregroundColor),
            ),
          ],
        ],
      ),
    );
  }
}
