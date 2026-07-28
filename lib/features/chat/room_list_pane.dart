import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';

/// 寄合（テキストチャンネル）1件分の一覧表示用の軽量データ。
/// 広場の`Room`・一対の`DmRoom`どちらもこの形にマッピングして渡す。
typedef RoomListEntry = ({String roomId, String name});

/// 友達一覧・広場一覧のサイドバーの右隣に表示する、選択中の会話の寄合
/// （テキストチャンネル）一覧サイドバー。広場・一対どちらでも使えるよう
/// データ・操作をすべてコールバック注入で受け取る汎用設計にしている
/// （`ChatScreen`が会話種別に依存しない設計を踏襲）。
///
/// 追加は確認無しで（名前を入力するダイアログのみで）即座に作成できる。
/// 削除は「本当に削除しますか？」の確認を挟む。[onCreateRoom]/
/// [onDeleteRoom]がnullの場合、それぞれの操作UI自体を出さない
/// （広場で長・モデレーターでないメンバーには削除ボタンを出さない、
/// 等の権限制御は呼び出し側がコールバックのnull/非nullで表現する）。
/// 寄合が1つしかない場合は、[onDeleteRoom]が非nullでも削除ボタンを
/// 無効化する（最後の1つは削除できないため）。
class RoomListPane extends ConsumerWidget {
  const RoomListPane({
    required this.roomsStream,
    required this.selectedRoomId,
    required this.onSelectRoom,
    this.onCreateRoom,
    this.onDeleteRoom,
    super.key,
  });

  final Stream<List<RoomListEntry>> roomsStream;
  final String? selectedRoomId;

  /// タップされた寄合そのもの（名前込み）を渡す。呼び出し側が名前を
  /// 再取得しなくても良いようにするため。
  final void Function(RoomListEntry room) onSelectRoom;
  final Future<void> Function(String name)? onCreateRoom;
  final Future<void> Function(String roomId)? onDeleteRoom;

  Future<void> _createRoom(
    BuildContext context,
    Strings strings,
    Vocabulary vocab,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.roomListAddDialogTitle(vocab.textChannel)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: vocab.textChannel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(strings.roomListAddButton),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await onCreateRoom?.call(name);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Strings strings,
    Vocabulary vocab,
    String roomId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.roomListDeleteConfirmTitle(vocab.textChannel)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.roomListDeleteConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed == true) await onDeleteRoom?.call(roomId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      child: StreamBuilder<List<RoomListEntry>>(
        stream: roomsStream,
        builder: (context, snapshot) {
          final rooms = snapshot.data ?? const [];
          final canDeleteAny = onDeleteRoom != null && rooms.length > 1;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        vocab.textChannel,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (onCreateRoom != null)
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => _createRoom(context, strings, vocab),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    for (final room in rooms)
                      ListTile(
                        selected: room.roomId == selectedRoomId,
                        selectedTileColor:
                            colorScheme.primaryContainer.withValues(alpha: 0.3),
                        leading: const Icon(Icons.tag),
                        title: Text(room.name),
                        onTap: () => onSelectRoom(room),
                        trailing: onDeleteRoom == null
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: canDeleteAny
                                    ? () => _confirmDelete(
                                          context,
                                          strings,
                                          vocab,
                                          room.roomId,
                                        )
                                    : null,
                              ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
