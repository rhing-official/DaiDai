import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../utils/text_truncate.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/gekiga/gekiga_text_field.dart';

/// 寄合（テキストチャンネル）1件分の一覧表示用の軽量データ。
/// 広場の`Room`・一対の`DmRoom`どちらもこの形にマッピングして渡す。
typedef RoomListEntry = ({String roomId, String name});

/// 友達一覧・広場一覧のサイドバーの右隣に表示する、選択中の会話の寄合
/// （テキストチャンネル）一覧サイドバー。広場・一対どちらでも使えるよう
/// データ・操作をすべてコールバック注入で受け取る汎用設計にしている
/// （`ChatScreen`が会話種別に依存しない設計を踏襲）。
///
/// 追加は確認無しで（名前を入力するダイアログのみで）即座に作成できる。
/// [onCreateRoom]がnullの場合、追加ボタン自体を出さない（広場で長・
/// モデレーターでないメンバーには出さない、等の権限制御は呼び出し側が
/// コールバックのnull/非nullで表現する）。
///
/// 削除はこのサイドバーからは行わない（旧: ごみ箱アイコン）。開いている
/// 寄合のハンバーガーメニュー「寄合を削除」から行う（2026-07-30変更、
/// `chat_panes.dart`の`_DmMenuButton`/`_GroupMenuButton`参照）。
///
/// [rooms]はStreamではなく解決済みの値で受け取る（以前はここで独自に
/// `Stream`を購読していたが、呼び出し側（`TalksTab`）が上位の会話一覧
/// 更新のたびにこのウィジェットを再構築し、その都度`roomsStream`に新しい
/// `Stream`インスタンスが渡ることで`StreamBuilder`が毎回購読し直され、
/// 寄合が一覧に定着して表示されない不具合があった。呼び出し側で1箇所だけ
/// 購読して得た最新値をそのまま渡す形にすることで解消した）。
class RoomListPane extends ConsumerWidget {
  const RoomListPane({
    required this.conversationName,
    required this.rooms,
    required this.selectedRoomId,
    required this.onSelectRoom,
    this.onCreateRoom,
    this.onOpenGroupSettings,
    super.key,
  });

  /// このペインが今表示している会話（広場名、または一対の相手の呼び名/
  /// Rhing ID）。ヘッダーに表示する（以前は用語「寄合」の固定文言だったが、
  /// どの会話の寄合一覧を見ているか分かりにくいとの指摘を受けて変更）。
  final String conversationName;

  final List<RoomListEntry> rooms;
  final String? selectedRoomId;

  /// タップされた寄合そのもの（名前込み）を渡す。呼び出し側が名前を
  /// 再取得しなくても良いようにするため。
  final void Function(RoomListEntry room) onSelectRoom;
  final Future<void> Function(String name)? onCreateRoom;

  /// 「広場自体の設定」を開く（サイドバーの歯車アイコン、2026-07-28追加）。
  /// 広場の長・モデレーターにのみ渡す。nullなら歯車アイコン自体を出さない
  /// （一対には広場設定という概念が無いため常にnull）。
  final VoidCallback? onOpenGroupSettings;

  Future<void> _createRoom(
    BuildContext context,
    Strings strings,
    Vocabulary vocab,
    bool isGekiga,
  ) async {
    final name = await promptForRoomName(context, strings, vocab, isGekiga);
    if (name == null || name.isEmpty) return;
    await onCreateRoom?.call(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    Widget buildRoomTile(RoomListEntry room) {
      final isSelected = room.roomId == selectedRoomId;

      if (isGekiga) {
        // 外枠は呼び出し側（下の`GekigaJointedTileList`）が寄合一覧全体を
        // まとめて描くため、ここでは内容だけを返す（2026-08-04変更）。
        return GekigaTileContent(
          selected: isSelected,
          leading: const Icon(Icons.tag),
          title: Text(
            truncateName(room.name, 6),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => onSelectRoom(room),
        );
      }

      return ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: isSelected,
        selectedTileColor: colorScheme.primary,
        selectedColor: colorScheme.onPrimary,
        leading: const Icon(Icons.tag),
        title: Text(
          truncateName(room.name, 6),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => onSelectRoom(room),
      );
    }

    return Material(
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: isGekiga
                      ? GekigaJointedTileList(
                          seeds: [conversationName.hashCode],
                          selectedFlags: const [false],
                          children: [
                            GekigaTileContent(
                              title: Text(
                                truncateName(conversationName, 8),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          truncateName(conversationName, 8),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
                if (onOpenGroupSettings != null)
                  isGekiga
                      ? GekigaIconButton(
                          icon: Icons.settings_outlined,
                          onPressed: onOpenGroupSettings!,
                        )
                      : IconButton(
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: onOpenGroupSettings,
                        ),
                if (onCreateRoom != null)
                  isGekiga
                      ? GekigaIconButton(
                          icon: Icons.add,
                          onPressed: () =>
                              _createRoom(context, strings, vocab, isGekiga),
                        )
                      : IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () =>
                              _createRoom(context, strings, vocab, isGekiga),
                        ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: isGekiga
                ? SingleChildScrollView(
                    // ヘッダー行と同じ左右の余白に揃える（2026-08-04追加）。
                    // 上にも余白を入れ、区切り線に一覧の箱が接して被って
                    // 見える不具合を解消する（2026-08-04追加）。
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: GekigaJointedTileList(
                      seeds: [for (final room in rooms) room.roomId.hashCode],
                      selectedFlags: [
                        for (final room in rooms) room.roomId == selectedRoomId,
                      ],
                      children: [for (final room in rooms) buildRoomTile(room)],
                    ),
                  )
                : ListView(
                    // 選択中タイルの塗り潰し（selectedTileColor）が、左右は
                    // カラム間のVerticalDividerに（2026-08-12追加）、上は
                    // ヘッダー直下のDividerに（同日追加）接して重なって
                    // 見えないよう余白を持たせる。上余白12pxは劇画UI分岐
                    // （上の`SingleChildScrollView`、2026-08-04追加）と揃えた。
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                    children: [for (final room in rooms) buildRoomTile(room)],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 寄合の新規追加ダイアログ（名前を入力するだけ、確認は無し）。
/// [RoomListPane]・[RoomTabBar]の両方から共通で使う（2026-08-03、
/// 横スクロールタブバー追加時に切り出した）。
Future<String?> promptForRoomName(
  BuildContext context,
  Strings strings,
  Vocabulary vocab, [
  bool isGekiga = false,
]) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.roomListAddDialogTitle(vocab.textChannel)),
      content: isGekiga
          ? GekigaTextField(
              controller: controller,
              autofocus: true,
              hintText: vocab.textChannel,
              onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
            )
          : TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(hintText: vocab.textChannel),
              onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
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
}
