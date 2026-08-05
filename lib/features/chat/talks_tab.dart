import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/conversation_prefs.dart';
import '../../models/direct_message.dart';
import '../../models/dm_room.dart';
import '../../models/friend_request.dart';
import '../../models/group.dart';
import '../../models/group_invite_preview.dart';
import '../../models/group_join_request.dart';
import '../../models/group_role.dart';
import '../../models/message.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/block_providers.dart';
import '../../providers/chat_navigation_providers.dart';
import '../../providers/conversation_prefs_providers.dart';
import '../../providers/friend_providers.dart';
import '../../providers/group_join_request_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_providers.dart';
import '../../router/app_router.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../utils/group_permissions.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/swipe_gestures.dart';
import 'add_chat_dialog.dart';
import 'chat_panes.dart';
import 'chat_screen.dart';
import 'create_group_dialog.dart';
import 'group_settings_popup.dart';
import 'room_list_pane.dart';

enum _TalksCategory { dm, group }

/// 画面幅がこれ以上あれば、一覧と会話を左右分割で同時表示する
/// （Discordのような「一覧は常に見えたまま、選んだ会話が右隣に開く」構成）。
/// これ未満の狭い画面では、従来通り会話をフルスクリーンで開く。
const kTalksSplitBreakpoint = 760.0;

/// 語らいタブの中身。上部の「一対」「広場」を横並びで切り替えて一覧表示する。
/// 相手の追加・広場の作成は、この画面内の＋ボタン（中央ポップアップ）から行う。
/// 一対タブの最上部には、届いている／送った友達申請が会話より先に表示される
/// （承認されて実際に会話が始まると、通常の一対リストの方へ下がっていく）。
class TalksTab extends ConsumerStatefulWidget {
  const TalksTab({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<TalksTab> createState() => _TalksTabState();
}

class _TalksTabState extends ConsumerState<TalksTab> {
  _TalksCategory _category = _TalksCategory.dm;
  DirectMessage? _selectedDm;
  Group? _selectedGroup;

  /// 承認待ちの一対・広場を選択中の場合の会話ペイン（2026-08-05追加）。
  /// `_selectedDm`/`_selectedGroup`と異なり、選択した時点で組み立てた
  /// `ChatScreen`（`disabled: true`）そのものをそのまま保持する。承認待ちの
  /// 間は実データが読めず、内容が更新されることも無いため、`_selectedDm`/
  /// `_selectedGroup`のような「最新スナップショットへの再解決」は不要。
  Widget? _selectedPendingScreen;

  /// 分割表示で現在表示中の寄合。nullなら選択中の会話の
  /// defaultRoomIdにフォールバックする（`_buildDmDetailWithRooms`/
  /// `_buildGroupDetailWithRooms`参照）。別の一対・広場を選び直すと
  /// nullに戻し、その会話のdefaultRoomIdから見せ直す。
  String? _selectedDmRoomId;
  String? _selectedGroupRoomId;

  /// 左右分割表示（[_isSplit]）の時、会話ペインを横いっぱいに広げて
  /// 一覧ペインを隠すか。横長のタブレット等で、固定幅の一覧に会話ペインの
  /// 幅を圧迫されず全画面で読みたい時のための切り替え。
  bool _chatExpanded = false;

  /// モバイルに限らず、縦表示（幅より高さの方が大きい）の場合は常に
  /// 横スクロールタブバー（[RoomTabBar]）でのドリルダウン表示にする
  /// （2026-08-04追加。以前は幅のみで判定しており、幅が広いタブレット等を
  /// 縦持ちにしても分割表示のままになっていた）。
  bool get _isSplit {
    final size = MediaQuery.sizeOf(context);
    return size.width >= kTalksSplitBreakpoint && size.width > size.height;
  }

  // 選択中の一対・広場の寄合一覧ストリームを、会話一覧の更新（新着メッセージ等）
  // ごとに再構築されるbuild()の中でも使い回すためのキャッシュ。以前は
  // _buildDmDetailWithRooms/_buildGroupDetailWithRoomsの中で毎回
  // watchRooms(id)を呼び直しており、上位のStreamBuilder<List<DirectMessage>>/
  // <List<Group>>が新着メッセージのたびに再描画されるとその都度Streamの
  // インスタンスが変わり、購読し直しになるせいでRoomListPaneの寄合一覧が
  // 定着して表示されない不具合があった（サイドバーを操作した瞬間だけ
  // 一時的に描画が追いつき、一瞬表示されて消えるように見えていた）。
  // 選択中のid（dmId/groupId）が変わった時だけ作り直す。
  String? _cachedDmRoomsId;
  Stream<List<DmRoom>>? _cachedDmRoomsStream;
  Stream<List<DmRoom>> _dmRoomsStream(String dmId) {
    if (_cachedDmRoomsId != dmId) {
      _cachedDmRoomsId = dmId;
      _cachedDmRoomsStream = ref
          .read(directMessageRepositoryProvider)
          .watchRooms(dmId: dmId, userId: widget.currentUser.userId);
    }
    return _cachedDmRoomsStream!;
  }

  String? _cachedGroupRoomsId;
  Stream<List<Room>>? _cachedGroupRoomsStream;
  Stream<List<Room>> _groupRoomsStream(String groupId) {
    if (_cachedGroupRoomsId != groupId) {
      _cachedGroupRoomsId = groupId;
      _cachedGroupRoomsStream = ref
          .read(groupRepositoryProvider)
          .watchRooms(groupId: groupId, userId: widget.currentUser.userId);
    }
    return _cachedGroupRoomsStream!;
  }

  /// 一対/広場タブを切り替える。承認待ちペイン（[_selectedPendingScreen]）は
  /// 表示中のタブに紐づくため、切り替え時にクリアする（2026-08-05追加）。
  void _setCategory(_TalksCategory category) {
    setState(() {
      _category = category;
      _selectedPendingScreen = null;
    });
  }

  /// 承認待ちの一対・広場のタイルをタップした時、分割表示なら一覧を
  /// 表示したまま右側のペインにその場で表示する（2026-08-05追加。
  /// 別ページを開く従来挙動は、分割表示ではない狭い画面でのみ使う）。
  void _selectPendingScreen(Widget screen) {
    setState(() {
      _selectedDm = null;
      _selectedGroup = null;
      _selectedPendingScreen = screen;
    });
  }

  Future<void> _openDirectMessage(DirectMessage dm) async {
    if (_isSplit) {
      setState(() {
        _selectedDm = dm;
        _selectedDmRoomId = null;
        _selectedPendingScreen = null;
      });
      return;
    }
    // 狭い画面では、複数モードでも寄合一覧のドリルダウン画面を経由せず、
    // 常にdefaultRoomIdでチャット画面へ直接遷移する。寄合の切り替えは
    // チャット画面上部の横スクロールタブバー（`RoomTabBar`）から行う
    // （2026-08-03変更、以前は複数モードのみ`/chat/dm-rooms`を経由していた）。
    final rooms = await _dmRoomsStream(dm.dmId).first;
    final roomName =
        rooms.firstWhereOrNull((r) => r.roomId == dm.defaultRoomId)?.name ??
        'メイン';
    ref
        .read(goRouterProvider)
        .push(
          '/chat/dm',
          extra: DmChatArgs(
            currentUser: widget.currentUser,
            dm: dm,
            roomId: dm.defaultRoomId,
            roomName: roomName,
          ),
        );
  }

  Future<void> _openGroup(Group group) async {
    if (_isSplit) {
      setState(() {
        _selectedGroup = group;
        _selectedGroupRoomId = null;
        _selectedPendingScreen = null;
      });
      return;
    }
    final rooms = await _groupRoomsStream(group.groupId).first;
    final roomName =
        rooms.firstWhereOrNull((r) => r.roomId == group.defaultRoomId)?.name ??
        'メイン';
    ref
        .read(goRouterProvider)
        .push(
          '/chat/group',
          extra: GroupChatArgs(
            currentUser: widget.currentUser,
            group: group,
            roomId: group.defaultRoomId,
            roomName: roomName,
          ),
        );
  }

  Future<void> _startCall(DirectMessage dm, {bool isVideo = false}) async {
    final callRepository = ref.read(callRepositoryProvider);
    final other = AppUser(
      userId: dm.otherUserId(widget.currentUser.userId),
      rhingId: dm.otherRhingId(widget.currentUser.userId),
    );
    final call = await callRepository.createCall(
      caller: widget.currentUser,
      callee: other,
      dmId: dm.dmId,
      isVideo: isVideo,
    );
    ref
        .read(goRouterProvider)
        .push(
          '/call',
          extra: CallArgs(
            call: call,
            isCaller: true,
            currentUserId: widget.currentUser.userId,
          ),
        );
  }

  /// 「＋」メニューポップアップの上に重ねて表示する2階層目のポップアップ
  /// （一対追加・広場作成、2026-07-29に画面遷移からポップアップ化）。
  /// [context]には呼び出し元のポップアップ自身のBuildContext（`dialogContext`）
  /// を渡す。1階層目を閉じずに開くことで、下に重なった状態で表示される。
  Future<void> _showStackedDialog(
    BuildContext context,
    Widget Function(VoidCallback closeSelf) contentBuilder,
  ) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (stackedContext, animation, secondaryAnimation) {
        return Center(
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
              child: contentBuilder(() => Navigator.of(stackedContext).pop()),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
    );
  }

  Future<void> _showAddMenu() async {
    final strings = ref.read(appStringsProvider);
    final vocab = ref.read(vocabularyProvider);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: strings.navTalk,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        // 注意: DialogをMaterial(color: transparent)で余分に包むと、
        // その外側Materialがタップを吸収してしまいバリアの外側タップ dismiss が効かなくなる
        // （実装内容.mdの経緯参照）。Dialogを直接Centerの子にすること。
        // 以前は縦積みのListTile2つ（無駄な余白が目立つ）だったが、
        // 中央の区切り線で左右2分割した大きめのカードに変更（2026-07-29）。
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return Center(
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SwipeDownToDismiss(
                onDismiss: () => Navigator.of(dialogContext).pop(),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _AddMenuOption(
                          icon: Icons.person_add_outlined,
                          title: strings.addMenuDmTitleTemplate(vocab.dm),
                          subtitle: strings.addMenuDmSubtitle,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(20),
                          ),
                          onTap: () => _showStackedDialog(
                            dialogContext,
                            (closeSelf) => AddChatDialogContent(
                              currentUser: widget.currentUser,
                              onClose: closeSelf,
                              onCompleted: () {
                                closeSelf();
                                Navigator.of(dialogContext).pop();
                              },
                            ),
                          ),
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: colorScheme.outlineVariant,
                      ),
                      Expanded(
                        child: _AddMenuOption(
                          icon: Icons.groups_outlined,
                          title: strings.addMenuGroupTitleTemplate(vocab.plaza),
                          subtitle: strings.addMenuGroupSubtitle,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(20),
                          ),
                          onTap: () => _showStackedDialog(
                            dialogContext,
                            (closeSelf) => CreateGroupDialogContent(
                              currentUser: widget.currentUser,
                              onClose: closeSelf,
                              onCompleted: () {
                                closeSelf();
                                Navigator.of(dialogContext).pop();
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        // 少し行き過ぎてから戻る、弾むような「ポップ」演出。
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // プロフィールカードダイアログ等、このWidgetツリーの外側から
    // 「この一対を開いてほしい」と伝えられた場合、一覧をクリックした時と
    // 全く同じ_openDirectMessageに渡す（サイドバー込みの表示を保つため、
    // 2026-07-29追加）。
    ref.listen<DirectMessage?>(pendingDmSelectionProvider, (previous, next) {
      if (next == null) return;
      ref.read(pendingDmSelectionProvider.notifier).clear();
      // 広場を見ている最中に相手の一対へジャンプした場合でも一対タブに
      // 切り替える（_categoryが広場のままだと_buildDetailPaneが広場側を
      // 表示し続けてしまうため）。
      setState(() => _category = _TalksCategory.dm);
      _openDirectMessage(next);
    });

    final vocab = ref.watch(vocabularyProvider);
    final groupsStream = ref
        .watch(groupRepositoryProvider)
        .watchGroups(widget.currentUser.userId);
    final directMessagesStream = ref
        .watch(directMessageRepositoryProvider)
        .watchDirectMessages(widget.currentUser.userId);
    final incomingRequests =
        ref
            .watch(incomingFriendRequestsProvider(widget.currentUser.userId))
            .value ??
        const [];
    final outgoingRequests =
        ref
            .watch(outgoingFriendRequestsProvider(widget.currentUser.userId))
            .value ??
        const [];
    final prefsById =
        ref.watch(conversationPrefsProvider(widget.currentUser.userId)).value ??
        const {};
    final blockedIds =
        ref.watch(blockedUserIdsProvider(widget.currentUser.userId)).value ??
        const {};
    final pendingGroupRequests =
        ref
            .watch(
              myPendingGroupJoinRequestsProvider(widget.currentUser.userId),
            )
            .value ??
        const [];

    final isSplit = _isSplit;

    return Scaffold(
      // 劇画スタイル時にホーム画面の背景装飾（ハーフトーン柄）を透過させる
      // 変更を一度試したが、リスト項目の隙間からドット柄が中途半端に透けて
      // しまい「赤一色の塗りつぶし」に見えないとの指摘を受け撤回した
      // （2026-08-04）。既定（`backgroundColor`未指定）のまま、テーマの
      // `scaffoldBackgroundColor`＝`GekigaColors.background`で不透明に塗る。
      body: StreamBuilder<List<DirectMessage>>(
        stream: directMessagesStream,
        builder: (context, dmSnapshot) {
          final directMessages = dmSnapshot.data ?? [];
          return StreamBuilder<List<Group>>(
            stream: groupsStream,
            builder: (context, groupSnapshot) {
              final groups = groupSnapshot.data ?? [];

              final listPane = Column(
                // 既定値（center）のままだと、一覧の中身（`GekigaJointedTileList`）
                // が自身の内容に応じた幅だけを主張し、その幅ぶん中央寄せされて
                // しまう。一対一覧と広場一覧では中身の最大幅が異なるため、
                // 中央寄せの基準がズレて左端の位置が一致しない不具合があった
                // （2026-08-04発覚・修正。`room_list_pane.dart`は元々`start`
                // 指定済みだったため同じ問題は起きていなかった）。
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        // 用語スタイルによってはラベルが長くなる
                        // （例:「ダイレクトメッセージ」「Terminology & display」相当）ため、
                        // 固定幅のサイドバーでも折り返さず、必要なときだけ
                        // 横スクロールできるようにして＋ボタンが押し出されないようにする。
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child:
                                ref.watch(appUiStyleProvider) ==
                                    AppUiStyle.gekiga
                                ? GekigaJointedPair(
                                    leftSeed: vocab.dm.hashCode,
                                    leftSelected:
                                        _category == _TalksCategory.dm,
                                    left: _CategoryTab(
                                      label: vocab.dm,
                                      count: directMessages.length,
                                      selected: _category == _TalksCategory.dm,
                                      onTap: () =>
                                          _setCategory(_TalksCategory.dm),
                                    ),
                                    rightSeed: vocab.plaza.hashCode,
                                    rightSelected:
                                        _category == _TalksCategory.group,
                                    right: _CategoryTab(
                                      label: vocab.plaza,
                                      count: groups.length,
                                      selected:
                                          _category == _TalksCategory.group,
                                      onTap: () =>
                                          _setCategory(_TalksCategory.group),
                                    ),
                                  )
                                : Row(
                                    children: [
                                      _CategoryTab(
                                        label: vocab.dm,
                                        count: directMessages.length,
                                        selected:
                                            _category == _TalksCategory.dm,
                                        onTap: () =>
                                            _setCategory(_TalksCategory.dm),
                                      ),
                                      const SizedBox(width: 20),
                                      _CategoryTab(
                                        label: vocab.plaza,
                                        count: groups.length,
                                        selected:
                                            _category == _TalksCategory.group,
                                        onTap: () =>
                                            _setCategory(_TalksCategory.group),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ref.watch(appUiStyleProvider) == AppUiStyle.gekiga
                            ? GekigaIconButton(
                                icon: Icons.add,
                                size: 32,
                                onPressed: _showAddMenu,
                              )
                            : IconButton.filled(
                                icon: const Icon(Icons.add, size: 20),
                                onPressed: _showAddMenu,
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(32, 32),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                      ],
                    ),
                  ),
                  // ヘッダー（一対/広場切り替えタブ）と一覧の間に隙間を空ける
                  // （2026-08-04追加、劇画スタイルのみ）。ジグザグ枠の箱が
                  // 隙間無くヘッダーのタブに接してしまい、被って見える
                  // 不具合があった。
                  if (ref.watch(appUiStyleProvider) == AppUiStyle.gekiga)
                    const SizedBox(height: 12),
                  Expanded(
                    // 横スワイプで一対⇄広場を切り替える。一対が先頭・広場が
                    // 2番目のタブなので、他タブの「前へ/次へ」パターンと同じ
                    // 向き（右スワイプ＝広場→一対、左スワイプ＝一対→広場）を
                    // そのまま流用する。戻る先の一覧が無いためonBackは空実装。
                    child: SwipeBackDetector(
                      onBack: () {},
                      onPrevious: _category == _TalksCategory.group
                          ? () => _setCategory(_TalksCategory.dm)
                          : null,
                      onNext: _category == _TalksCategory.dm
                          ? () => _setCategory(_TalksCategory.group)
                          : null,
                      child: _category == _TalksCategory.dm
                          ? _buildDirectMessages(
                              dmSnapshot,
                              directMessages,
                              incomingRequests,
                              outgoingRequests,
                              prefsById,
                              blockedIds,
                            )
                          : _buildGroups(
                              groupSnapshot,
                              groups,
                              prefsById,
                              pendingGroupRequests,
                            ),
                    ),
                  ),
                ],
              );

              if (!isSplit) return listPane;

              // 会話ペインでの横スワイプで一覧の表示/非表示を切り替える
              // （一覧側のスワイプは既に一対⇄広場の切り替えに使っているため、
              // ここは会話ペインのみに閉じたジェスチャーにする）。
              // 左スワイプ＝広げる、右スワイプ＝戻す、という他画面と同じ
              // 「進む/戻る」の向きに合わせている。
              final detailPane = SwipeBackDetector(
                onBack: () => setState(() => _chatExpanded = false),
                onNext: () => setState(() => _chatExpanded = true),
                child: _buildDetailPane(directMessages, groups),
              );

              if (_chatExpanded) return detailPane;

              return Row(
                children: [
                  SizedBox(width: 360, child: listPane),
                  const VerticalDivider(width: 1),
                  Expanded(child: detailPane),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// 選択中の会話ペインを、その時点の会話一覧（Firestoreの最新スナップショット）
  /// から解決して構築する。`_selectedDm`/`_selectedGroup`は選択した瞬間の
  /// スナップショットのままなので、これをそのまま`DmChatPane`/`GroupChatPane`に
  /// 渡すと、選択後に相手側でプロフィールカード等を更新しても、一覧の再選択や
  /// 画面再読み込みをするまで古い内容のまま表示され続けてしまう（一覧自体は
  /// 各StreamBuilderで直接再描画されるため最新化されるが、選択状態はここでしか
  /// 保持していないため）。選択中IDに一致する最新の要素があればそちらを使う。
  Widget _buildDetailPane(
    List<DirectMessage> directMessages,
    List<Group> groups,
  ) {
    final pending = _selectedPendingScreen;
    if (pending != null) return pending;
    if (_category == _TalksCategory.dm) {
      final selected = _selectedDm;
      if (selected == null) return const _EmptyDetailPlaceholder();
      final dm = directMessages.firstWhere(
        (d) => d.dmId == selected.dmId,
        orElse: () => selected,
      );
      return _buildDmDetailWithRooms(dm);
    }
    final selected = _selectedGroup;
    if (selected == null) return const _EmptyDetailPlaceholder();
    final group = groups.firstWhere(
      (g) => g.groupId == selected.groupId,
      orElse: () => selected,
    );
    return _buildGroupDetailWithRooms(group);
  }

  /// 選択中の一対を、寄合一覧サイドバー＋選択中の寄合のChatScreenの
  /// 2ペイン構成で表示する。`_selectedDmRoomId`が現在の寄合一覧に無い
  /// （未選択・削除された等）場合はdefaultRoomIdにフォールバックする。
  Widget _buildDmDetailWithRooms(DirectMessage dm) {
    final dmRepository = ref.read(directMessageRepositoryProvider);
    final otherUserId = dm.otherUserId(widget.currentUser.userId);
    final otherUser = ref.watch(watchedUserProvider(otherUserId)).value;
    final otherNickname = otherUser?.effectiveNicknameFor(dm.dmId)?.text;
    final conversationName = (otherNickname?.isNotEmpty ?? false)
        ? otherNickname!
        : '@${dm.otherRhingId(widget.currentUser.userId)}';
    return StreamBuilder<List<DmRoom>>(
      stream: _dmRoomsStream(dm.dmId),
      builder: (context, snapshot) {
        final rooms = snapshot.data ?? const <DmRoom>[];
        final roomId =
            (_selectedDmRoomId != null &&
                rooms.any((r) => r.roomId == _selectedDmRoomId))
            ? _selectedDmRoomId!
            : dm.defaultRoomId;
        final roomName = rooms
            .firstWhere(
              (r) => r.roomId == roomId,
              orElse: () => DmRoom(
                roomId: roomId,
                dmId: dm.dmId,
                name: 'メイン',
                participants: dm.participants,
              ),
            )
            .name;
        return Row(
          children: [
            // 単一モードではサイドバーを出さない（2026-07-29追加、
            // `DirectMessage.roomsEnabled`参照）。寄合を増やす操作は
            // ハンバーガーメニューから行う（`_DmMenuButton`参照）。
            if (dm.roomsEnabled) ...[
              SizedBox(
                width: 220,
                child: RoomListPane(
                  conversationName: conversationName,
                  rooms: [
                    for (final r in rooms) (roomId: r.roomId, name: r.name),
                  ],
                  selectedRoomId: roomId,
                  onSelectRoom: (room) =>
                      setState(() => _selectedDmRoomId = room.roomId),
                  onCreateRoom: (name) =>
                      dmRepository.createRoom(dmId: dm.dmId, name: name),
                ),
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: DmChatPane(
                key: ValueKey('detail-dm-${dm.dmId}-$roomId'),
                currentUser: widget.currentUser,
                dm: dm,
                roomId: roomId,
                roomName: roomName,
                onCallPressed: () => _startCall(dm),
                onVideoCallPressed: () => _startCall(dm, isVideo: true),
              ),
            ),
          ],
        );
      },
    );
  }

  /// [_buildDmDetailWithRooms]と同じ構成の広場版。寄合の追加・削除は
  /// manageRooms権限を持つメンバーのみ（firestore.rulesで強制、ここでは
  /// UI上の操作可否も合わせる）。
  Widget _buildGroupDetailWithRooms(Group group) {
    final groupRepository = ref.read(groupRepositoryProvider);
    final userId = widget.currentUser.userId;
    final canManageRooms = hasGroupPermission(
      group: group,
      userId: userId,
      permission: GroupPermission.manageRooms,
    );
    return StreamBuilder<List<Room>>(
      stream: _groupRoomsStream(group.groupId),
      builder: (context, snapshot) {
        final rooms = snapshot.data ?? const <Room>[];
        final roomId =
            (_selectedGroupRoomId != null &&
                rooms.any((r) => r.roomId == _selectedGroupRoomId))
            ? _selectedGroupRoomId!
            : group.defaultRoomId;
        final roomName = rooms
            .firstWhere(
              (r) => r.roomId == roomId,
              orElse: () => Room(
                roomId: roomId,
                groupId: group.groupId,
                name: 'メイン',
                memberIds: group.memberIds,
              ),
            )
            .name;
        return Row(
          children: [
            // 単一モードではサイドバーを出さない（2026-07-29追加、
            // `Group.roomsEnabled`参照）。「広場自体の設定」・寄合を増やす
            // 操作はハンバーガーメニューから行う（`_GroupMenuButton`参照）。
            if (group.roomsEnabled) ...[
              SizedBox(
                width: 220,
                child: RoomListPane(
                  conversationName: group.name,
                  rooms: [
                    for (final r in rooms) (roomId: r.roomId, name: r.name),
                  ],
                  selectedRoomId: roomId,
                  onSelectRoom: (room) =>
                      setState(() => _selectedGroupRoomId = room.roomId),
                  onCreateRoom: canManageRooms
                      ? (name) => groupRepository.createRoom(
                          groupId: group.groupId,
                          name: name,
                        )
                      : null,
                  // 全体設定ポップアップ自体は全メンバーが開ける
                  // （中の各項目が個別に権限ゲートされる、2026-07-29変更。
                  // 以前はcanManageRolesの間だけロール管理を直接開いていた）。
                  onOpenGroupSettings: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 420,
                          maxHeight: 640,
                        ),
                        child: GroupSettingsPopup(
                          currentUser: widget.currentUser,
                          group: group,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: GroupChatPane(
                key: ValueKey('detail-group-${group.groupId}-$roomId'),
                currentUser: widget.currentUser,
                group: group,
                roomId: roomId,
                roomName: roomName,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDirectMessages(
    AsyncSnapshot<List<DirectMessage>> snapshot,
    List<DirectMessage> directMessages,
    List<FriendRequest> incomingRequests,
    List<FriendRequest> outgoingRequests,
    Map<String, ConversationPrefs> prefsById,
    Set<String> blockedIds,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        incomingRequests.isEmpty &&
        outgoingRequests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    // ブロックした相手は一対の一覧から非表示にする（会話・ブロック状態自体は
    // 保持したまま、一覧に出さないだけ。ブロック解除は設定＞語らいから行う）。
    final visibleDms = directMessages
        .where(
          (dm) =>
              !blockedIds.contains(dm.otherUserId(widget.currentUser.userId)),
        )
        .toList();
    if (visibleDms.isEmpty &&
        incomingRequests.isEmpty &&
        outgoingRequests.isEmpty) {
      final dmTerm = ref.read(vocabularyProvider).dm;
      return Center(child: Text('まだ$dmTermがありません。上の＋から相手を追加してください。'));
    }

    final sortedDms = _sortedByPin(visibleDms, prefsById, (dm) => dm.dmId);

    if (ref.watch(appUiStyleProvider) == AppUiStyle.gekiga) {
      final seeds = <int>[
        for (final request in incomingRequests) request.requestId.hashCode,
        for (final request in outgoingRequests) request.requestId.hashCode,
        for (final dm in sortedDms) dm.dmId.hashCode,
      ];
      final selectedFlags = <bool>[
        for (final _ in incomingRequests) false,
        for (final _ in outgoingRequests) false,
        for (final dm in sortedDms) _isSplit && _selectedDm?.dmId == dm.dmId,
      ];
      final children = <Widget>[
        for (final request in incomingRequests)
          _FriendRequestTile(
            currentUserId: widget.currentUser.userId,
            request: request,
            isSplit: _isSplit,
            onSelectPending: _selectPendingScreen,
          ),
        for (final request in outgoingRequests)
          _FriendRequestTile(
            currentUserId: widget.currentUser.userId,
            request: request,
            isSplit: _isSplit,
            onSelectPending: _selectPendingScreen,
          ),
        for (final dm in sortedDms)
          _DirectMessageTile(
            currentUser: widget.currentUser,
            dm: dm,
            pinned: prefsById[dm.dmId]?.pinned ?? false,
            muted: prefsById[dm.dmId]?.notificationsMuted ?? false,
            selected: _isSplit && _selectedDm?.dmId == dm.dmId,
            onTap: () => _openDirectMessage(dm),
          ),
      ];
      return SingleChildScrollView(
        // ヘッダー（一対/広場切り替えタブの行）と同じ左右の余白
        // （`EdgeInsets.fromLTRB(16, 12, 16, 0)`）に揃える（2026-08-04
        // 修正。以前は左右の余白が無く、一覧の箱がサイドバーの左端に
        // ぴったり付いてしまい、ヘッダーのタブより左に飛び出して見える
        // 不具合があった）。
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GekigaJointedTileList(
          seeds: seeds,
          selectedFlags: selectedFlags,
          children: children,
        ),
      );
    }

    return ListView(
      children: [
        for (final request in incomingRequests)
          _FriendRequestTile(
            currentUserId: widget.currentUser.userId,
            request: request,
            isSplit: _isSplit,
            onSelectPending: _selectPendingScreen,
          ),
        for (final request in outgoingRequests)
          _FriendRequestTile(
            currentUserId: widget.currentUser.userId,
            request: request,
            isSplit: _isSplit,
            onSelectPending: _selectPendingScreen,
          ),
        for (final dm in sortedDms)
          _DirectMessageTile(
            currentUser: widget.currentUser,
            dm: dm,
            pinned: prefsById[dm.dmId]?.pinned ?? false,
            muted: prefsById[dm.dmId]?.notificationsMuted ?? false,
            selected: _isSplit && _selectedDm?.dmId == dm.dmId,
            onTap: () => _openDirectMessage(dm),
          ),
      ],
    );
  }

  Widget _buildGroups(
    AsyncSnapshot<List<Group>> snapshot,
    List<Group> groups,
    Map<String, ConversationPrefs> prefsById,
    List<GroupJoinRequest> pendingRequests,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        pendingRequests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (groups.isEmpty && pendingRequests.isEmpty) {
      final plazaTerm = ref.read(vocabularyProvider).plaza;
      return Center(child: Text('まだ$plazaTermがありません。上の＋から作成してください。'));
    }
    final sortedGroups = _sortedByPin(groups, prefsById, (g) => g.groupId);

    if (ref.watch(appUiStyleProvider) == AppUiStyle.gekiga) {
      final seeds = <int>[
        for (final request in pendingRequests) request.requestId.hashCode,
        for (final group in sortedGroups) group.groupId.hashCode,
      ];
      final selectedFlags = <bool>[
        for (final _ in pendingRequests) false,
        for (final group in sortedGroups)
          _isSplit && _selectedGroup?.groupId == group.groupId,
      ];
      final children = <Widget>[
        for (final request in pendingRequests)
          _PendingGroupJoinRequestTile(
            request: request,
            isSplit: _isSplit,
            onSelectPending: _selectPendingScreen,
          ),
        for (final group in sortedGroups)
          _GroupTile(
            currentUserId: widget.currentUser.userId,
            group: group,
            pinned: prefsById[group.groupId]?.pinned ?? false,
            muted: prefsById[group.groupId]?.notificationsMuted ?? false,
            selected: _isSplit && _selectedGroup?.groupId == group.groupId,
            onTap: () => _openGroup(group),
          ),
      ];
      return SingleChildScrollView(
        // ヘッダー（一対/広場切り替えタブの行）と同じ左右の余白
        // （`EdgeInsets.fromLTRB(16, 12, 16, 0)`）に揃える（2026-08-04
        // 修正。以前は左右の余白が無く、一覧の箱がサイドバーの左端に
        // ぴったり付いてしまい、ヘッダーのタブより左に飛び出して見える
        // 不具合があった）。
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GekigaJointedTileList(
          seeds: seeds,
          selectedFlags: selectedFlags,
          children: children,
        ),
      );
    }

    return ListView(
      children: [
        for (final request in pendingRequests)
          _PendingGroupJoinRequestTile(
            request: request,
            isSplit: _isSplit,
            onSelectPending: _selectPendingScreen,
          ),
        for (final group in sortedGroups)
          _GroupTile(
            currentUserId: widget.currentUser.userId,
            group: group,
            pinned: prefsById[group.groupId]?.pinned ?? false,
            muted: prefsById[group.groupId]?.notificationsMuted ?? false,
            selected: _isSplit && _selectedGroup?.groupId == group.groupId,
            onTap: () => _openGroup(group),
          ),
      ],
    );
  }

  static List<T> _sortedByPin<T>(
    List<T> items,
    Map<String, ConversationPrefs> prefsById,
    String Function(T) idOf,
  ) {
    final pinned = <T>[];
    final unpinned = <T>[];
    for (final item in items) {
      if (prefsById[idOf(item)]?.pinned ?? false) {
        pinned.add(item);
      } else {
        unpinned.add(item);
      }
    }
    return [...pinned, ...unpinned];
  }
}

/// 「一対」「広場」を横並びで切り替えるタブ。件数チップ付き。
/// 劇画スタイルでは選択中=白地黒字／未選択=黒地白字のモノクロボックス
/// （[GekigaJointedPair]）にする（2026-08-03追加、appUiStyleProviderを見る
/// ためConsumerWidget化）。
class _CategoryTab extends ConsumerWidget {
  const _CategoryTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    if (isGekiga) {
      // 外枠（モノクロボックス）は呼び出し側の`GekigaJointedPair`が
      // 2つのタブをまとめて描くため、ここでは内容（Material+InkWell+Text）
      // だけを返す（2026-08-04変更、以前は`GekigaPanelBox`で自前で囲んで
      // いた）。
      final fg = selected ? GekigaColors.panel : GekigaColors.onPanel;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            // 縦幅・フォントサイズをシンプルスタイル側（vertical:6,
            // fontSize:16）に揃える（2026-08-04変更）。横方向だけは、
            // シンプル側に無いジグザグ枠の線に文字が重ならないよう
            // 14を維持する。
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text(
              '$label $count',
              style: TextStyle(
                color: fg,
                fontSize: 16,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final color = selected ? colorScheme.primary : Colors.grey;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: color,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 届いている／送った友達申請を表す行。一対リストの最上部に表示される。
/// 自分が送った友達申請・広場参加リクエストがまだ承認されていない間、
/// タップした時に開く軽量なプレビュー画面。実際のメッセージ画面
/// （`ChatScreen`）はfirestore.rules上、未承認の間は`rooms`/`messages`
/// サブコレクションを読めず開けないため、タイトル（相手の呼び名/広場名）
/// と「承認を待っています」系の文言だけを表示する専用画面で代替する
/// （2026-08-04追加）。`Scaffold`/`AppBar`はisGekiga分岐を持たず、
/// アンビエントの`Theme`（劇画スタイルなら`GekigaTheme`）にそのまま従う。
/// 承認待ちの一対・広場を開いたときに、メッセージ一覧の上に常時表示する
/// バナー（[ChatScreen.banner]に渡す。`chat_panes.dart`の
/// `_SeveranceBanner`等と同じ用途だが、操作ボタンを持たない読み取り専用、
/// 2026-08-05新規）。
class _PendingApprovalBanner extends StatelessWidget {
  const _PendingApprovalBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

class _FriendRequestTile extends ConsumerWidget {
  const _FriendRequestTile({
    required this.currentUserId,
    required this.request,
    required this.isSplit,
    required this.onSelectPending,
  });

  final String currentUserId;
  final FriendRequest request;

  /// 分割表示中かどうか。trueなら承認待ちタップ時に[onSelectPending]で
  /// 右側のペインへその場で表示し、falseなら別ページを開く（2026-08-05追加）。
  final bool isSplit;
  final ValueChanged<Widget> onSelectPending;

  bool get _isIncoming => request.toUserId == currentUserId;

  String get _otherUserId => currentUserId == request.fromUserId
      ? request.toUserId
      : request.fromUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final otherUser = ref.watch(watchedUserProvider(_otherUserId)).value;
    // まだ一対が成立していなくても、dmIdは決定的に計算できるため
    // （`DirectMessage.idFor`）、相手が申請送信時に選んだ会話ごとの
    // プロフィールカードがあればそれを反映して表示する（2026-07-29追加）。
    final dmId = DirectMessage.idFor(currentUserId, _otherUserId);
    final iconUrl = otherUser?.effectiveIconFor(dmId)?.url;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    final leadingWidget = CircleAvatar(
      backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
      child: iconUrl == null ? const Icon(Icons.person_outline) : null,
    );
    final titleText = '@${request.otherRhingId(currentUserId)}';
    // outgoing（自分が送った申請）は「相手の承認を待っています」という
    // 待ちの情報を、一覧のブロックからは消してタップ時のプレビュー画面側に
    // 表示する（2026-08-04変更）。incoming（相手から届いた申請）は
    // 承認/却下ボタンがあるため現状のまま変更しない。
    final subtitleWidget = _isIncoming
        ? Text(strings.friendRequestIncomingSubtitle)
        : null;
    final trailingWidget = _isIncoming
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => ref
                    .read(friendRepositoryProvider)
                    .respond(request: request, accept: false),
                child: Text(strings.friendRequestDecline),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () => ref
                    .read(friendRepositoryProvider)
                    .respond(request: request, accept: true),
                child: Text(strings.friendRequestAccept),
              ),
            ],
          )
        : null;
    final onTap = _isIncoming
        ? null
        : () {
            final screen = ChatScreen(
              title: titleText,
              currentUserId: currentUserId,
              isDm: true,
              messagesStream: Stream.value(const <Message>[]),
              onSend: (_, {silent = false, replyTo}) async {},
              disabled: true,
              banner: _PendingApprovalBanner(
                message: strings.friendRequestOutgoingSubtitle,
              ),
            );
            if (isSplit) {
              onSelectPending(screen);
            } else {
              Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => screen));
            }
          };

    if (isGekiga) {
      return GekigaTileContent(
        leading: leadingWidget,
        title: Text(titleText),
        subtitle: subtitleWidget,
        trailing: trailingWidget,
        onTap: onTap,
      );
    }

    return ListTile(
      leading: leadingWidget,
      title: Text(titleText),
      subtitle: subtitleWidget,
      trailing: trailingWidget,
      onTap: onTap,
    );
  }
}

/// 自分が送った、承認待ちの広場参加リクエストを一覧の先頭に表示するタイル。
/// タップしても実際の広場は開けない（まだメンバーではないため）ので、
/// 承認待ちであることを伝える[_PendingApprovalScreen]を開く
/// （2026-08-04変更、以前はAlertDialogだった）。
class _PendingGroupJoinRequestTile extends ConsumerWidget {
  const _PendingGroupJoinRequestTile({
    required this.request,
    required this.isSplit,
    required this.onSelectPending,
  });

  final GroupJoinRequest request;

  /// [_FriendRequestTile.isSplit]と同じ（2026-08-05追加）。
  final bool isSplit;
  final ValueChanged<Widget> onSelectPending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    return FutureBuilder<GroupInvitePreview?>(
      future: ref
          .read(groupRepositoryProvider)
          .getInvitePreview(request.groupId),
      builder: (context, snapshot) {
        final preview = snapshot.data;
        final leadingWidget = CircleAvatar(
          backgroundImage: preview?.iconUrl != null
              ? NetworkImage(preview!.iconUrl!)
              : null,
          child: preview?.iconUrl == null
              ? const Icon(Icons.hourglass_top_outlined)
              : null,
        );
        final titleText = preview?.name ?? '...';
        void onTap() {
          final screen = ChatScreen(
            title: titleText,
            currentUserId: request.requesterId,
            isDm: false,
            messagesStream: Stream.value(const <Message>[]),
            onSend: (_, {silent = false, replyTo}) async {},
            disabled: true,
            banner: _PendingApprovalBanner(message: strings.groupJoinPending),
          );
          if (isSplit) {
            onSelectPending(screen);
          } else {
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => screen));
          }
        }

        if (isGekiga) {
          return GekigaTileContent(
            leading: leadingWidget,
            title: Text(titleText),
            onTap: onTap,
          );
        }

        return ListTile(
          leading: leadingWidget,
          title: Text(titleText),
          onTap: onTap,
        );
      },
    );
  }
}

class _DirectMessageTile extends ConsumerWidget {
  const _DirectMessageTile({
    required this.currentUser,
    required this.dm,
    required this.pinned,
    required this.muted,
    required this.onTap,
    this.selected = false,
  });

  final AppUser currentUser;
  final DirectMessage dm;
  final bool pinned;
  final bool muted;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otherUserId = dm.otherUserId(currentUser.userId);
    final otherUser = ref.watch(watchedUserProvider(otherUserId)).value;
    final nickname = otherUser?.effectiveNicknameFor(dm.dmId)?.text;
    final label = (nickname?.isNotEmpty ?? false)
        ? nickname!
        : '@${dm.otherRhingId(currentUser.userId)}';
    final iconUrl = otherUser?.effectiveIconFor(dm.dmId)?.url;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    final leadingWidget = CircleAvatar(
      backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
      child: iconUrl == null ? const Icon(Icons.person) : null,
    );
    final trailingWidget = _ConversationIndicators(
      pinned: pinned,
      muted: muted,
    );

    if (isGekiga) {
      return _ConversationGestures(
        conversationId: dm.dmId,
        userId: currentUser.userId,
        pinned: pinned,
        muted: muted,
        child: GekigaTileContent(
          selected: selected,
          leading: leadingWidget,
          title: Text(label),
          trailing: trailingWidget,
          onTap: onTap,
        ),
      );
    }

    return _ConversationGestures(
      conversationId: dm.dmId,
      userId: currentUser.userId,
      pinned: pinned,
      muted: muted,
      child: ListTile(
        selected: selected,
        selectedTileColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.08),
        leading: leadingWidget,
        title: Text(label),
        trailing: trailingWidget,
        onTap: onTap,
      ),
    );
  }
}

class _GroupTile extends ConsumerWidget {
  const _GroupTile({
    required this.currentUserId,
    required this.group,
    required this.pinned,
    required this.muted,
    required this.onTap,
    this.selected = false,
  });

  final String currentUserId;
  final Group group;
  final bool pinned;
  final bool muted;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconUrl = group.profileCard?.iconUrl;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;

    final leadingWidget = CircleAvatar(
      backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
      child: iconUrl == null ? const Icon(Icons.groups) : null,
    );
    final trailingWidget = _ConversationIndicators(
      pinned: pinned,
      muted: muted,
    );

    if (isGekiga) {
      return _ConversationGestures(
        conversationId: group.groupId,
        userId: currentUserId,
        pinned: pinned,
        muted: muted,
        child: GekigaTileContent(
          selected: selected,
          leading: leadingWidget,
          title: Text(group.name),
          subtitle: Text('${group.memberIds.length}人'),
          trailing: trailingWidget,
          onTap: onTap,
        ),
      );
    }

    return _ConversationGestures(
      conversationId: group.groupId,
      userId: currentUserId,
      pinned: pinned,
      muted: muted,
      child: ListTile(
        selected: selected,
        selectedTileColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.08),
        leading: leadingWidget,
        title: Text(group.name),
        subtitle: Text('${group.memberIds.length}人'),
        trailing: trailingWidget,
        onTap: onTap,
      ),
    );
  }
}

/// ピン留め・通知オフのアイコン表示（両方falseなら何も出さない）。
class _ConversationIndicators extends StatelessWidget {
  const _ConversationIndicators({required this.pinned, required this.muted});

  final bool pinned;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    if (!pinned && !muted) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (muted)
          const Icon(
            Icons.notifications_off_outlined,
            size: 18,
            color: Colors.grey,
          ),
        if (pinned) ...[
          if (muted) const SizedBox(width: 4),
          Icon(
            Icons.push_pin,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ],
    );
  }
}

/// 右クリック（デスクトップ）・長押し（モバイル）で、ピン留め・通知オフのメニューを出す。
class _ConversationGestures extends ConsumerWidget {
  const _ConversationGestures({
    required this.conversationId,
    required this.userId,
    required this.pinned,
    required this.muted,
    required this.child,
  });

  final String conversationId;
  final String userId;
  final bool pinned;
  final bool muted;
  final Widget child;

  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final strings = ref.read(appStringsProvider);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'pin',
          child: Text(
            pinned ? strings.conversationUnpin : strings.conversationPin,
          ),
        ),
        PopupMenuItem(
          value: 'mute',
          child: Text(
            muted ? strings.conversationUnmute : strings.conversationMute,
          ),
        ),
      ],
    );
    if (selected == 'pin') {
      await ref
          .read(conversationPrefsRepositoryProvider)
          .setPinned(
            userId: userId,
            conversationId: conversationId,
            pinned: !pinned,
          );
    } else if (selected == 'mute') {
      await ref
          .read(conversationPrefsRepositoryProvider)
          .setNotificationsMuted(
            userId: userId,
            conversationId: conversationId,
            muted: !muted,
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showMenu(context, ref, details.globalPosition),
      onLongPressStart: (details) =>
          _showMenu(context, ref, details.globalPosition),
      child: child,
    );
  }
}

/// 「＋」ポップアップの左右どちらか半分を占める、大きめのタップ可能領域
/// （2026-07-29、縦積みのListTileから中央区切り線の2分割カードへ変更）。
class _AddMenuOption extends StatelessWidget {
  const _AddMenuOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.borderRadius,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: borderRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分割ビューで会話が未選択のときに右側に表示するプレースホルダー。
class _EmptyDetailPlaceholder extends StatelessWidget {
  const _EmptyDetailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.forum_outlined,
        size: 64,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}
