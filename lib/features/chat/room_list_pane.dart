import 'package:flutter/foundation.dart' show setEquals;
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
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/glass/glass_surface.dart';

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
class RoomListPane extends ConsumerStatefulWidget {
  const RoomListPane({
    required this.conversationName,
    required this.rooms,
    required this.selectedRoomId,
    required this.onSelectRoom,
    this.onCreateRoom,
    this.onOpenConversationSettings,
    this.onReorderRooms,
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

  /// 「広場自体の設定」/「一対の設定」を開く（サイドバーの歯車アイコン、
  /// 2026-07-28追加、2026-09-13に一対にも配線）。広場は長・モデレーターにのみ
  /// 渡す。nullなら歯車アイコン自体を出さない。
  final VoidCallback? onOpenConversationSettings;

  /// 寄合一覧の並べ替え（ブロック左端のハンドルをドラッグ、2026-09-08追加）。
  /// 並べ替え後の寄合idの並びを渡す。nullなら並べ替え機能自体を出さない
  /// （広場で`manageRooms`権限を持たないメンバーには渡さない）。
  final Future<void> Function(List<String> roomIds)? onReorderRooms;

  @override
  ConsumerState<RoomListPane> createState() => _RoomListPaneState();
}

class _RoomListPaneState extends ConsumerState<RoomListPane> {
  /// ドラッグ中・保存の往復中も体感が即応するよう、[widget.rooms]から
  /// 同期したローカルの並びを保持する（`GroupRolePriorityDialog`と異なり
  /// 保存ボタンは無く、並べ替えのたびに逐次[RoomListPane.onReorderRooms]で
  /// 保存するため）。id集合が変わらない限りは外部からの再構築で並びを
  /// 巻き戻さない（自分の並べ替えがFirestoreを経由して戻ってきただけの
  /// 場合と、他のメンバーが同時に並べ替えた場合を区別できないため、後者は
  /// 次にid集合が変わるタイミング＝寄合の追加・削除時まで反映が遅れる
  /// 既知の制約として許容する）。
  late List<RoomListEntry> _rooms = List.of(widget.rooms);

  @override
  void didUpdateWidget(covariant RoomListPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentIds = _rooms.map((r) => r.roomId).toSet();
    final incomingIds = widget.rooms.map((r) => r.roomId).toSet();
    if (!setEquals(currentIds, incomingIds)) {
      _rooms = List.of(widget.rooms);
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

  void _handleReorder(int index, int newIndex) {
    setState(() {
      final room = _rooms.removeAt(index);
      _rooms.insert(newIndex, room);
    });
    widget.onReorderRooms?.call([for (final r in _rooms) r.roomId]);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;

    // [index]は並べ替え有効時（[RoomListPane.onReorderRooms]非null）のみ
    // 渡され、`leading`にドラッグハンドルを追加する（2026-09-08追加）。
    Widget buildRoomTile(RoomListEntry room, {int? index}) {
      final isSelected = room.roomId == widget.selectedRoomId;
      final tagIcon = index == null
          ? const Icon(Icons.tag)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_indicator, size: 18),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.tag),
              ],
            );

      if (isGekiga) {
        // 外枠は呼び出し側（下の`GekigaJointedTileList`）が寄合一覧全体を
        // まとめて描くため、ここでは内容だけを返す（2026-08-04変更）。
        return GekigaTileContent(
          selected: isSelected,
          leading: tagIcon,
          title: Text(
            truncateName(room.name, 6),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => widget.onSelectRoom(room),
        );
      }

      if (isGlass) {
        // 選択・非選択で文字色は変えない（背景の塗りだけで選択状態を表す）。
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: GlassSurface(
            variant: GlassVariant.card,
            borderRadius: BorderRadius.circular(12),
            accentColorOverride: isSelected ? colorScheme.primary : null,
            child: Material(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.45)
                  : Colors.transparent,
              child: ListTile(
                iconColor: colorScheme.onSurfaceVariant,
                textColor: colorScheme.onSurfaceVariant,
                leading: tagIcon,
                title: Text(
                  truncateName(room.name, 6),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => widget.onSelectRoom(room),
              ),
            ),
          ),
        );
      }

      return ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: isSelected,
        selectedTileColor: colorScheme.primary,
        selectedColor: colorScheme.onPrimary,
        leading: tagIcon,
        title: Text(
          truncateName(room.name, 6),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => widget.onSelectRoom(room),
      );
    }

    final paneContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: isGekiga
                    ? GekigaJointedTileList(
                        seeds: [widget.conversationName.hashCode],
                        selectedFlags: const [false],
                        children: [
                          GekigaTileContent(
                            title: Text(
                              truncateName(widget.conversationName, 8),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        truncateName(widget.conversationName, 8),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
              if (widget.onOpenConversationSettings != null)
                isGekiga
                    ? GekigaIconButton(
                        icon: Icons.settings_outlined,
                        onPressed: widget.onOpenConversationSettings!,
                      )
                    : IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: widget.onOpenConversationSettings,
                      ),
              if (widget.onCreateRoom != null)
                isGekiga
                    ? GekigaIconButton(
                        icon: Icons.add,
                        onPressed: () => _createRoom(
                          context,
                          strings,
                          vocab,
                          isGekiga,
                          isGlass,
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => _createRoom(
                          context,
                          strings,
                          vocab,
                          isGekiga,
                          isGlass,
                        ),
                      ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: isGekiga && widget.onReorderRooms == null
              ? SingleChildScrollView(
                  // ヘッダー行と同じ左右の余白に揃える（2026-08-04追加）。
                  // 上にも余白を入れ、区切り線に一覧の箱が接して被って
                  // 見える不具合を解消する（2026-08-04追加）。
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: GekigaJointedTileList(
                    seeds: [for (final room in _rooms) room.roomId.hashCode],
                    selectedFlags: [
                      for (final room in _rooms)
                        room.roomId == widget.selectedRoomId,
                    ],
                    children: [for (final room in _rooms) buildRoomTile(room)],
                  ),
                )
              : !isGekiga && widget.onReorderRooms == null
              ? ListView(
                  // 選択中タイルの塗り潰し（selectedTileColor）が、左右は
                  // カラム間のVerticalDividerに（2026-08-12追加）、上は
                  // ヘッダー直下のDividerに（同日追加）接して重なって
                  // 見えないよう余白を持たせる。上余白12pxは劇画UI分岐
                  // （上の`SingleChildScrollView`、2026-08-04追加）と揃えた。
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                  children: [for (final room in _rooms) buildRoomTile(room)],
                )
              : ReorderableListView(
                  // ブロック左端のドラッグハンドル（`Icons.drag_indicator`、
                  // `buildRoomTile`参照）のみでドラッグを開始させ、行本体の
                  // タップ＝寄合選択と競合しないようにする（2026-09-08追加）。
                  // 劇画UIも他のUIスタイルと同じくこの分岐で並べ替える
                  // （2026-09-12追加、以前は劇画UIだけ非対応だった。
                  // `GekigaJointedTileList`は2026-08-05の変更で複数の箱を
                  // 接合せず、間隔を空けてそれぞれ独立した箱として描くように
                  // なっているため、1件だけ渡しても他の項目と見た目が変わらない
                  // 独立した箱になる＝`ReorderableListView`の1行として個別に
                  // ドラッグできる）。
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                  onReorderItem: _handleReorder,
                  children: [
                    for (final (index, room) in _rooms.indexed)
                      KeyedSubtree(
                        key: ValueKey(room.roomId),
                        child: isGekiga
                            ? GekigaJointedTileList(
                                seeds: [room.roomId.hashCode],
                                selectedFlags: [
                                  room.roomId == widget.selectedRoomId,
                                ],
                                children: [buildRoomTile(room, index: index)],
                              )
                            : buildRoomTile(room, index: index),
                      ),
                  ],
                ),
        ),
      ],
    );

    return isGlass
        ? GlassSurface(
            variant: GlassVariant.chrome,
            borderRadius: BorderRadius.zero,
            enableEdgeStroke: false,
            child: Material(color: Colors.transparent, child: paneContent),
          )
        : Material(color: colorScheme.surface, child: paneContent);
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
  bool isGlass = false,
]) {
  final controller = TextEditingController();
  final title = Text(strings.roomListAddDialogTitle(vocab.textChannel));
  final content = isGekiga
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
        );
  final actions = [
    TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(strings.cancel),
    ),
    FilledButton(
      onPressed: () => Navigator.of(context).pop(controller.text.trim()),
      child: Text(strings.roomListAddButton),
    ),
  ];
  return showDialog<String>(
    context: context,
    // ガラスUIは素の`AlertDialog`だと`GlassTheme.dialogTheme.background
    // Color`がColors.transparentのため、実際の塗り・ぼかしを描く
    // `GlassSurface`でラップしていないと背景が透明のまま素通しになる
    // （2026-09-11発覚・修正、`group_delete_dialog.dart`等と同じ
    // `isGlass ? Dialog(child: GlassAlertDialog(...)) : AlertDialog(...)`
    // 分岐に揃えた）。
    builder: (context) => isGlass
        ? ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: GlassAlertDialog(
              title: title,
              content: content,
              actions: actions,
            ),
          )
        : AlertDialog(
            constraints: const BoxConstraints(maxWidth: 400),
            title: title,
            content: content,
            actions: actions,
          ),
  );
}
