import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/conversation_prefs.dart';
import '../../models/conversation_sort_order.dart';
import '../../models/direct_message.dart';
import '../../models/dm_room.dart';
import '../../models/friend_request.dart';
import '../../models/group.dart';
import '../../models/group_invite_preview.dart';
import '../../models/group_join_request.dart';
import '../../models/group_role.dart';
import '../../models/message.dart';
import '../../models/talks_list_layout_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/block_providers.dart';
import '../../providers/chat_navigation_providers.dart';
import '../../providers/chat_room_message_cache.dart';
import '../../providers/conversation_prefs_providers.dart';
import '../../providers/conversation_sort_order_provider.dart';
import '../../providers/friend_providers.dart';
import '../../providers/group_join_request_providers.dart';
import '../../providers/message_time_format_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/talks_list_layout_style_provider.dart';
import '../../providers/user_providers.dart';
import '../../router/app_router.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/motion.dart';
import '../../theme/text_prominence_colors.dart';
import '../../utils/drag_menu_geometry.dart';
import '../../utils/group_permissions.dart';
import '../../utils/kana_sort.dart';
import '../../utils/message_time.dart';
import '../../utils/official_account.dart';
import '../../utils/platform_info.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/gekiga/gekiga_text_field.dart';
import '../../widgets/glass/glass_icon_badge.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/interactive_swipe_back.dart';
import '../../widgets/swipe_gestures.dart';
import '../call/active_call_session.dart';
import 'add_chat_dialog.dart';
import 'chat_panes.dart';
import 'chat_screen.dart';
import 'create_group_dialog.dart';
import 'group_settings_popup.dart';
import 'room_list_pane.dart';
import 'talks_search.dart';

enum _TalksCategory { dm, group }

/// 画面幅がこれ以上あれば、一覧と会話を左右分割で同時表示する
/// （Discordのような「一覧は常に見えたまま、選んだ会話が右隣に開く」構成）。
/// これ未満の狭い画面では、従来通り会話をフルスクリーンで開く。
const kTalksSplitBreakpoint = 760.0;

/// 縦表示の「アイコン+寄合一覧」レイアウト（[TalksListLayoutStyle.iconSplit]）で、
/// 寄合一覧の右隣にメッセージ画面も同時表示するかどうかを判定する横幅の閾値
/// （`home_screen.dart`の`_kWideLayoutBreakpoint`と同じ値、タブレット・
/// コンピューター相当、2026-09-12追加）。これ未満の幅（スマホ縦表示相当）では、
/// 画面が狭くメッセージ画面を同時に収められないため、従来通り寄合をタップした
/// 時点でフルスクリーンチャットへ遷移する。
const kIconSplitPeekBreakpoint = 600.0;

/// [kIconSplitPeekBreakpoint]以上の縦表示で寄合一覧＋メッセージ画面を同時
/// 表示する時の、アイコン列＋寄合一覧（畳める部分）の合計幅（2026-09-12追加）。
/// アイコン列112px＋区切り線1px＋寄合一覧220px。ドラッグの進行度計算と、
/// 畳んだ時に実際に隠す幅の両方で使う。
const kIconSplitCollapseWidth = 112.0 + 1.0 + 220.0;

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

class _TalksTabState extends ConsumerState<TalksTab>
    with SingleTickerProviderStateMixin {
  _TalksCategory _category = _TalksCategory.dm;
  DirectMessage? _selectedDm;
  Group? _selectedGroup;

  /// [_buildIconRail]で検索欄を表示中か（2026-09-12追加）。この列は112px幅しか
  /// 無く、標準レイアウトの`_buildSearchField`のようにタブ＋検索欄を常設で
  /// 並べる余白が無いため、検索アイコンのタップでタブ表示と切り替える。
  bool _iconRailSearchOpen = false;

  /// [_buildIconSplitPane]の3ブロック同時表示（タブレット・コンピューター
  /// 縦表示のみ）で、寄合一覧を左スワイプした時の指追従アニメーションの
  /// 進行度（2026-09-12追加）。0=通常の3ブロック表示、1=アイコン列・
  /// 寄合一覧を完全に畳んでメッセージ画面を全画面表示。`ValueNotifier`に
  /// しているのは、ドラッグ中に毎フレーム`setState`すると（Firestore購読を
  /// 抱えた）タブ全体が再構築されてしまうのを避け、実際に畳む幅計算だけを
  /// 行う`_CollapsibleWidthPanel`だけを再描画するため。
  final ValueNotifier<double> _iconSplitCollapse = ValueNotifier(0);

  /// [_iconSplitCollapse]をドラッグ終了後に0/1へ収束させるアニメーション
  /// （[InteractiveSwipeBackController]と同じ設計、2026-09-12追加）。
  late final AnimationController _iconSplitCollapseAnimController =
      AnimationController(vsync: this);

  /// ドラッグ中の累積移動量（px）。[_iconSplitCollapse]は0〜1の比率で
  /// 保持するため、ドラッグ開始時に現在の比率からpx換算で復元する。
  double _iconSplitCollapseDragCumulative = 0;

  /// 今回のドラッグジェスチャーで[_iconSplitCollapse]の変更を許可するか
  /// （2026-09-12追加）。「畳む」操作はメッセージ画面のクリック専用にした
  /// （[_DmDetailWithRoomsState]/[_GroupDetailWithRoomsState]の
  /// `onExpandTap`）ため、既に全開（`_iconSplitCollapse.value == 0`）の
  /// 状態から始まるドラッグは無視し、「開く」方向（既に畳まれている状態から
  /// の右ドラッグ）だけを受け付ける。
  bool _iconSplitDragEnabled = false;

  /// 一対⇄広場の横スワイプ切り替え用（2026-08-09追加、`SwipeBackDetector`の
  /// 速度しきい値判定から`PageView`へ変更。手描きの速度判定だと片方向だけ
  /// ジェスチャーアリーナで負けて反応しないことがあったため、この用途では
  /// 双方向のスワイプ切り替えが実績豊富な`PageView`に任せる）。
  late final PageController _categoryPageController = PageController(
    initialPage: _category.index,
  );

  /// 一対・広場を横断して検索するための入力欄（2026-08-30追加）。
  final _searchController = TextEditingController();

  /// メッセージ内容検索のセッション（2026-09-12追加、検索欄を開いている間の
  /// 取得済みメッセージのメモ化キャッシュを持つ）。`_buildSearchResults`と
  /// `_buildIconRail`のインライン検索の両方で共用する（画面幅・向きで
  /// どちらか一方しか同時に表示されないため）。
  final _messageSearchSession = TalksMessageSearchSession();

  /// [_messageSearchSession]のデバウンス用タイマー。
  Timer? _messageSearchDebounce;

  /// 直近のメッセージ内容検索結果（2026-09-12追加）。`_onSearchTextChanged`が
  /// デバウンス後に更新する。
  List<MessageSearchHit> _messageMatches = const [];

  void _onSearchTextChanged() {
    setState(() {});
    _messageSearchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.length < kMinMessageSearchQueryLength) {
      _messageSearchSession.clear();
      if (_messageMatches.isNotEmpty) {
        setState(() => _messageMatches = const []);
      }
      return;
    }
    _messageSearchDebounce = Timer(kMessageSearchDebounce, () async {
      final hits = await _messageSearchSession.search(
        query: query,
        currentUserId: widget.currentUser.userId,
        directMessages: _lastDirectMessages,
        groups: _lastGroups,
        blockedIds: _lastBlockedIds,
        dmRepository: ref.read(directMessageRepositoryProvider),
        groupRepository: ref.read(groupRepositoryProvider),
        cacheManager: ref.read(chatRoomMessageCacheManagerProvider),
      );
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() => _messageMatches = hits);
    });
  }

  /// [_onSearchTextChanged]がデバウンス後の検索実行時に参照する、直近の
  /// build()時点の一対・広場・ブロック一覧のスナップショット（2026-09-12
  /// 追加）。`build()`はStreamBuilderのネストの奥で組み立てられるため、
  /// デバウンスタイマーのコールバック（build()の外）から直接参照できる
  /// 場所にキャッシュしておく。
  List<DirectMessage> _lastDirectMessages = const [];
  List<Group> _lastGroups = const [];
  Set<String> _lastBlockedIds = const {};

  @override
  void dispose() {
    _categoryPageController.dispose();
    _searchController.dispose();
    _messageSearchDebounce?.cancel();
    _iconSplitCollapse.dispose();
    _iconSplitCollapseAnimController.dispose();
    super.dispose();
  }

  /// [_buildIconSplitPane]の寄合一覧（＋アイコン列）を右にドラッグして開き
  /// 直す時のハンドラ（2026-09-12追加）。[InteractiveSwipeBackTransition]の
  /// 「戻る」ドラッグと同じ設計で、ドラッグ中は指の位置にリアルタイムに
  /// 追従し、離した時点の速度／位置で開く・畳んだままを確定してアニメーション
  /// で収束させる。「畳む」操作自体はメッセージ画面のクリック専用
  /// （`onExpandTap`）にしたため、[_iconSplitDragEnabled]が立っている
  /// （＝既に畳まれている）時しか反応しない。
  void _handleIconSplitDragStart(DragStartDetails details) {
    _iconSplitDragEnabled = _iconSplitCollapse.value > 0;
    if (!_iconSplitDragEnabled) return;
    _iconSplitCollapseAnimController.stop();
    _iconSplitCollapseDragCumulative =
        _iconSplitCollapse.value * kIconSplitCollapseWidth;
  }

  void _handleIconSplitDragUpdate(DragUpdateDetails details) {
    if (!_iconSplitDragEnabled) return;
    // 左ドラッグ（dx負）で畳む＝progress増加、右ドラッグ（dx正）で開く＝
    // progress減少という向きにするため、dxを引く。
    _iconSplitCollapseDragCumulative -= details.delta.dx;
    _iconSplitCollapse.value =
        (_iconSplitCollapseDragCumulative / kIconSplitCollapseWidth).clamp(
          0.0,
          1.0,
        );
  }

  void _handleIconSplitDragEnd(DragEndDetails details) {
    if (!_iconSplitDragEnabled) return;
    final velocity = details.primaryVelocity ?? 0;
    final bool collapse;
    if (velocity <= -kSwipeGestureVelocityThreshold) {
      collapse = true;
    } else if (velocity >= kSwipeGestureVelocityThreshold) {
      collapse = false;
    } else {
      collapse = _iconSplitCollapse.value >= 0.5;
    }
    _animateIconSplitCollapse(collapse ? 1.0 : 0.0);
  }

  void _animateIconSplitCollapse(double target) {
    final start = _iconSplitCollapse.value;
    final fraction = (target - start).abs();
    final duration = Duration(
      milliseconds: (popSlideDuration.inMilliseconds * fraction).round().clamp(
        120,
        popSlideDuration.inMilliseconds,
      ),
    );
    _iconSplitCollapseAnimController
      ..duration = duration
      ..value = 0;
    final animation = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(
        parent: _iconSplitCollapseAnimController,
        curve: popSlideCurve,
      ),
    );
    void listener() => _iconSplitCollapse.value = animation.value;
    animation.addListener(listener);
    _iconSplitCollapseAnimController.forward().whenCompleteOrCancel(
      () => animation.removeListener(listener),
    );
  }

  /// 承認待ちの一対・広場を選択中の場合の会話ペイン（2026-08-05追加）。
  /// `_selectedDm`/`_selectedGroup`と異なり、選択した時点で組み立てた
  /// `ChatScreen`（`disabled: true`）そのものをそのまま保持する。承認待ちの
  /// 間は実データが読めず、内容が更新されることも無いため、`_selectedDm`/
  /// `_selectedGroup`のような「最新スナップショットへの再解決」は不要。
  Widget? _selectedPendingScreen;

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

  /// [_buildIconSplitPane]（`TalksListLayoutStyle.iconSplit`）で、寄合一覧の
  /// 右隣にメッセージ画面本体も同時表示する「3ブロック表示」を使うか
  /// （2026-09-12追加）。タブレット・コンピューターの縦表示相当（幅
  /// [kIconSplitPeekBreakpoint]以上かつ縦表示）でのみtrueになる。
  /// [_openDirectMessage]/[_openGroup]が「寄合を複数化していない会話でも
  /// ローカル表示にするか」の判定にも使うため、`_buildIconSplitPane`内だけに
  /// 閉じていたローカル変数から昇格させた。
  bool get _showIconSplitPeek {
    final size = MediaQuery.sizeOf(context);
    return size.height > size.width && size.width >= kIconSplitPeekBreakpoint;
  }

  /// 分割表示でこのセッション中に一度でも開いた会話（`'dm-$dmId'`/
  /// `'group-$groupId'`）を挿入順に記録する（2026-08-20追加、語らい切り替え
  /// ラグの解消）。[_buildDetailPane]がこの集合の全件を`IndexedStack`で
  /// 裏側に保持し続けることで、別の会話に切り替えて戻ってきてもChatScreenの
  /// 作り直し（Firestore購読のやり直し）が起きなくなる。会話が削除されると
  /// [_buildDetailPane]が集合から取り除く。上限は設けない（ページ再読み込み
  /// でリセットされるため許容、ユーザー確認済み）。
  final LinkedHashSet<String> _visitedConversationKeys =
      LinkedHashSet<String>();

  /// 一対/広場タブを切り替える（タブ見出しのタップ用）。承認待ちペイン
  /// （[_selectedPendingScreen]）は表示中のタブに紐づくため、切り替え時に
  /// クリアする（2026-08-05追加）。`_categoryPageController`がまだ
  /// 該当ページを表示していなければアニメーションで追従させる
  /// （2026-08-09追加、スワイプ側の[_handleCategoryPageChanged]と役割分担）。
  void _setCategory(_TalksCategory category) {
    setState(() {
      _category = category;
      _selectedPendingScreen = null;
    });
    if (_categoryPageController.hasClients &&
        _categoryPageController.page?.round() != category.index) {
      _categoryPageController.animateToPage(
        category.index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  /// `_categoryPageController`のスワイプでページが確定した時に呼ばれる
  /// （2026-08-09追加）。[_setCategory]と異なり、既にその位置までページが
  /// 動き終えているためコントローラのアニメーションは行わない。
  void _handleCategoryPageChanged(int index) {
    setState(() {
      _category = _TalksCategory.values[index];
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
    // 縦表示のアイコン＋寄合一覧レイアウト（`TalksListLayoutStyle.iconSplit`）
    // では、複数寄合モードの会話は広い画面の分割表示と同じく選択状態にして
    // 右側に寄合一覧を出す。単一モードの会話は右ペインを経由する意味が
    // 無いため、従来通りその場でフルスクリーンチャットへ遷移する
    // （2026-09-11追加）。ただし[_showIconSplitPeek]（タブレット・
    // コンピューター縦表示でアイコン列＋寄合一覧＋メッセージ画面を同時表示
    // するモード）の間は、単一モードの会話でもコンピューターの横表示
    // （`_isSplit`）と同様にアイコン列を残したままその場で表示したいため、
    // `roomsEnabled`を問わず選択状態にする（2026-09-12追加）。
    final useIconSplitSelection =
        !_isSplit &&
        (dm.roomsEnabled || _showIconSplitPeek) &&
        ref.read(talksListLayoutStyleProvider) ==
            TalksListLayoutStyle.iconSplit;
    if (_isSplit || useIconSplitSelection) {
      // 別の会話に切り替えたら、直前の会話で畳んでいた状態
      // （[_iconSplitCollapse]）を引き継がず、寄合一覧から見せ直す
      // （2026-09-12追加）。
      _iconSplitCollapse.value = 0;
      setState(() {
        _selectedDm = dm;
        _selectedPendingScreen = null;
      });
      return;
    }
    // 狭い画面では、複数モードでも寄合一覧のドリルダウン画面を経由せず、
    // 常に一番上の寄合でチャット画面へ直接遷移する。寄合の切り替えは
    // チャット画面上部の横スクロールタブバー（`RoomTabBar`）から行う
    // （2026-08-03変更、以前は複数モードのみ`/chat/dm-rooms`を経由していた。
    // 2026-08-09変更、defaultRoomId固定だったものを一番上（最古）の寄合を
    // 開くように変更）。
    final rooms = await ref
        .read(directMessageRepositoryProvider)
        .watchRooms(dmId: dm.dmId, userId: widget.currentUser.userId)
        .first;
    final topRoomId = rooms.isNotEmpty ? rooms.first.roomId : dm.defaultRoomId;
    final roomName =
        rooms.firstWhereOrNull((r) => r.roomId == topRoomId)?.name ?? 'メイン';
    ref
        .read(goRouterProvider)
        .push(
          '/chat/dm',
          extra: DmChatArgs(
            currentUser: widget.currentUser,
            dm: dm,
            roomId: topRoomId,
            roomName: roomName,
            enterFromRight: true,
          ),
        );
  }

  Future<void> _openGroup(Group group) async {
    // [_openDirectMessage]と同じ理由（2026-09-11追加、2026-09-12更新）。
    final useIconSplitSelection =
        !_isSplit &&
        (group.roomsEnabled || _showIconSplitPeek) &&
        ref.read(talksListLayoutStyleProvider) ==
            TalksListLayoutStyle.iconSplit;
    if (_isSplit || useIconSplitSelection) {
      // [_openDirectMessage]と同じ理由（2026-09-12追加）。
      _iconSplitCollapse.value = 0;
      setState(() {
        _selectedGroup = group;
        _selectedPendingScreen = null;
      });
      return;
    }
    // 一対と同じく、一番上（最古）の寄合を開く（2026-08-09変更）。
    final rooms = await ref
        .read(groupRepositoryProvider)
        .watchRooms(groupId: group.groupId, userId: widget.currentUser.userId)
        .first;
    final topRoomId = rooms.isNotEmpty
        ? rooms.first.roomId
        : group.defaultRoomId;
    final roomName =
        rooms.firstWhereOrNull((r) => r.roomId == topRoomId)?.name ?? 'メイン';
    ref
        .read(goRouterProvider)
        .push(
          '/chat/group',
          extra: GroupChatArgs(
            currentUser: widget.currentUser,
            group: group,
            roomId: topRoomId,
            roomName: roomName,
            enterFromRight: true,
          ),
        );
  }

  /// 語らい検索のメッセージ内容一致（[MessageSearchHit]）をタップした時に
  /// 開く（2026-09-12追加）。[_openDirectMessage]/[_openGroup]と同じ
  /// 分割表示・アイコン+寄合一覧の判定を踏襲するが、v1のメッセージ内容検索が
  /// 各語らいの既定寄合（`defaultRoomId`）しか対象にしていないため、
  /// `topRoomId`解決を経由せず必ず[hit.roomId]（＝既定寄合）を直接開く。
  /// 該当メッセージまでのジャンプ＆ハイライトは[pendingMessageJumpProvider]
  /// 経由で`ChatScreen`側に伝える（`chat_navigation_providers.dart`参照）。
  Future<void> _openMessageSearchHit(MessageSearchHit hit) async {
    final conversation = hit.isDm
        ? ViewedDm(hit.dm!.dmId)
        : ViewedGroup(hit.group!.groupId);
    final roomsEnabled = hit.isDm
        ? hit.dm!.roomsEnabled
        : hit.group!.roomsEnabled;
    final useIconSplitSelection =
        !_isSplit &&
        (roomsEnabled || _showIconSplitPeek) &&
        ref.read(talksListLayoutStyleProvider) ==
            TalksListLayoutStyle.iconSplit;

    ref
        .read(pendingMessageJumpProvider.notifier)
        .set(conversation, hit.message.messageId);

    if (_isSplit || useIconSplitSelection) {
      _iconSplitCollapse.value = 0;
      setState(() {
        if (hit.isDm) {
          _category = _TalksCategory.dm;
          _selectedDm = hit.dm;
          _selectedGroup = null;
        } else {
          _category = _TalksCategory.group;
          _selectedGroup = hit.group;
          _selectedDm = null;
        }
        _selectedPendingScreen = null;
      });
      return;
    }

    if (hit.isDm) {
      final dm = hit.dm!;
      final rooms = await ref
          .read(directMessageRepositoryProvider)
          .watchRooms(dmId: dm.dmId, userId: widget.currentUser.userId)
          .first;
      final roomName =
          rooms.firstWhereOrNull((r) => r.roomId == hit.roomId)?.name ?? 'メイン';
      ref
          .read(goRouterProvider)
          .push(
            '/chat/dm',
            extra: DmChatArgs(
              currentUser: widget.currentUser,
              dm: dm,
              roomId: hit.roomId,
              roomName: roomName,
              enterFromRight: true,
            ),
          );
    } else {
      final group = hit.group!;
      final rooms = await ref
          .read(groupRepositoryProvider)
          .watchRooms(groupId: group.groupId, userId: widget.currentUser.userId)
          .first;
      final roomName =
          rooms.firstWhereOrNull((r) => r.roomId == hit.roomId)?.name ?? 'メイン';
      ref
          .read(goRouterProvider)
          .push(
            '/chat/group',
            extra: GroupChatArgs(
              currentUser: widget.currentUser,
              group: group,
              roomId: hit.roomId,
              roomName: roomName,
              enterFromRight: true,
            ),
          );
    }
  }

  /// 「＋」メニューポップアップの上に重ねて表示する2階層目のポップアップ
  /// （一対追加・広場作成、2026-07-29に画面遷移からポップアップ化）。
  /// [context]には呼び出し元のポップアップ自身のBuildContext（`dialogContext`）
  /// を渡す。1階層目を閉じずに開くことで、下に重なった状態で表示される。
  Future<void> _showStackedDialog(
    BuildContext context,
    Widget Function(VoidCallback closeSelf) contentBuilder,
  ) {
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (stackedContext, animation, secondaryAnimation) {
        final content = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
          child: contentBuilder(() => Navigator.of(stackedContext).pop()),
        );
        return Center(
          child: Dialog(
            backgroundColor: isGlass ? Colors.transparent : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: isGlass
                ? GlassSurface(
                    variant: GlassVariant.floating,
                    borderRadius: BorderRadius.circular(20),
                    child: content,
                  )
                : content,
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
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
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
        // GlassSurfaceも同じ理由でMaterialを持たない実装にしており、
        // 中身の実サイズにフィットするため、この注意点は引き続き問題ない。
        final colorScheme = Theme.of(dialogContext).colorScheme;
        final menuContent = SwipeDownToDismiss(
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
        );
        final content = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: menuContent,
        );
        return Center(
          child: Dialog(
            backgroundColor: isGlass ? Colors.transparent : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: isGlass
                ? GlassSurface(
                    variant: GlassVariant.floating,
                    borderRadius: BorderRadius.circular(20),
                    child: content,
                  )
                : content,
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
    // 通話ミニ表示（PinnedCallOverlay）タップでの復帰用（2026-08-19追加）。
    // 上のDM版と同じ橋渡しパターン。
    ref.listen<Group?>(pendingGroupSelectionProvider, (previous, next) {
      if (next == null) return;
      ref.read(pendingGroupSelectionProvider.notifier).clear();
      setState(() => _category = _TalksCategory.group);
      _openGroup(next);
    });

    final vocab = ref.watch(vocabularyProvider);
    final strings = ref.watch(appStringsProvider);
    final searchQuery = _searchController.text.trim().toLowerCase();
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
    final talksListLayoutStyle = ref.watch(talksListLayoutStyleProvider);

    return Scaffold(
      // 劇画スタイル時にホーム画面の背景装飾（ハーフトーン柄）を透過させる
      // 変更を一度試したが、リスト項目の隙間からドット柄が中途半端に透けて
      // しまい「赤一色の塗りつぶし」に見えないとの指摘を受け撤回した
      // （2026-08-04）。既定（`backgroundColor`未指定）のまま、テーマの
      // `scaffoldBackgroundColor`＝`GekigaColors.background`で不透明に塗る。
      body: StreamBuilder<List<DirectMessage>>(
        stream: directMessagesStream,
        builder: (context, dmSnapshot) {
          final directMessages = (dmSnapshot.data ?? [])
              .where(
                (dm) =>
                    dm.otherUserId(widget.currentUser.userId) !=
                    officialAccountUid,
              )
              .toList();
          return StreamBuilder<List<Group>>(
            stream: groupsStream,
            builder: (context, groupSnapshot) {
              final groups = groupSnapshot.data ?? [];
              // `_onSearchTextChanged`のデバウンスコールバック（build()の外）
              // から参照するためのスナップショット（2026-09-12追加）。
              _lastDirectMessages = directMessages;
              _lastGroups = groups;
              _lastBlockedIds = blockedIds;

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
                        // 言語によってはラベルが長くなる（例: 英語の
                        // "Private"/"Plaza"は日本語の「一対」「広場」より幅を
                        // 取る）。以前は幅が収まらない場合`Wrap`で折り返す形に
                        // していたが、英語表示時に2つのチップの合計幅が
                        // 入りきらず縦並びに見えてしまう不具合があった。横
                        // スクロールで逃がす方式も試したが、常に横並びで
                        // スクロール無しに収めたいとのユーザー要望のため
                        // 採用せず、代わりに`_CategoryTab`側のパディング・
                        // フォントサイズを詰めて260px幅のサイドバーに折り返し・
                        // スクロールいずれも無しで収まるようにした
                        // （2026-08-27発覚・修正）。
                        Expanded(
                          child:
                              ref.watch(appUiStyleProvider) == AppUiStyle.gekiga
                              ? SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: GekigaJointedPair(
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
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _CategoryTab(
                                      label: vocab.dm,
                                      count: directMessages.length,
                                      selected: _category == _TalksCategory.dm,
                                      onTap: () =>
                                          _setCategory(_TalksCategory.dm),
                                    ),
                                    const SizedBox(width: 6),
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
                        const SizedBox(width: 8),
                        switch (ref.watch(appUiStyleProvider)) {
                          AppUiStyle.gekiga => GekigaIconButton(
                            icon: Icons.add,
                            size: 32,
                            onPressed: _showAddMenu,
                          ),
                          AppUiStyle.glass => GlassIconButton(
                            icon: Icons.add,
                            size: 32,
                            onPressed: _showAddMenu,
                          ),
                          AppUiStyle.flat => IconButton.filled(
                            icon: const Icon(Icons.add, size: 20),
                            onPressed: _showAddMenu,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(32, 32),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        },
                      ],
                    ),
                  ),
                  // 一対/広場切り替えタブの真下に検索欄を置く（2026-08-30
                  // 追加）。検索中は下のExpandedの中身がカテゴリ別スワイプ
                  // 表示から検索結果一覧に切り替わる。並べ替えボタンは
                  // 検索欄の右隣に置く（2026-09-02追加）。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        Expanded(child: _buildSearchField(strings)),
                        const SizedBox(width: 8),
                        _buildSortButton(strings),
                      ],
                    ),
                  ),
                  // ヘッダー（一対/広場切り替えタブ）と一覧の間に隙間を空ける
                  // （2026-08-04追加、劇画スタイルのみ→2026-08-12全スタイル
                  // 共通に変更）。劇画スタイルはジグザグ枠の箱が隙間無く
                  // ヘッダーのタブに接してしまい被って見える不具合、フラット
                  // スタイルは選択中チップの塗り潰しと一覧の先頭行が隙間無く
                  // 接して重なって見える不具合が、それぞれあった。
                  const SizedBox(height: 12),
                  Expanded(
                    child: searchQuery.isEmpty
                        ? PageView(
                            // 横スワイプで一対⇄広場を切り替える。速度しきい値
                            // 判定の自前ジェスチャー（`SwipeBackDetector`）だと
                            // 片方向だけジェスチャーアリーナで負けて反応しない
                            // ことがあったため、双方向のページ送りが実績豊富な
                            // `PageView`に置き換えた（2026-08-09変更、
                            // 2026-08-06時点では速度しきい値の条件式自体を
                            // 両方向常時有効にする修正をしていたが、それでも
                            // 一対→広場方向が反応しない場合が残っていた）。
                            controller: _categoryPageController,
                            onPageChanged: _handleCategoryPageChanged,
                            children: [
                              _buildDirectMessages(
                                dmSnapshot,
                                directMessages,
                                incomingRequests,
                                outgoingRequests,
                                prefsById,
                                blockedIds,
                              ),
                              _buildGroups(
                                groupSnapshot,
                                groups,
                                prefsById,
                                pendingGroupRequests,
                              ),
                            ],
                          )
                        : _buildSearchResults(
                            searchQuery,
                            directMessages,
                            groups,
                            prefsById,
                            blockedIds,
                            strings,
                          ),
                  ),
                ],
              );

              if (!isSplit) {
                if (talksListLayoutStyle == TalksListLayoutStyle.iconSplit) {
                  return _buildIconSplitPane(
                    directMessages,
                    groups,
                    prefsById,
                    incomingRequests,
                    outgoingRequests,
                    pendingGroupRequests,
                    blockedIds,
                  );
                }
                return listPane;
              }

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
                  // 260px: 語らい一覧のブロック（アイコン＋名前＋ピン/ミュート
                  // アイコン）が重ならない範囲でできるだけ狭め、メッセージ画面
                  // 側に幅を譲っている（2026-08-05再変更、360→300→240。2026-08-13に
                  // 一旦300へ戻したのは、240だとEnglish表示時の一対/広場切り替え
                  // タブ（"Private N"/"Plaza N"）＋追加ボタンが収まりきらなかった
                  // ため。2026-08-14、区切り線の位置を設定サイドバー
                  // （`_kSettingsSidebarWidth`）・身だしなみサイドバー
                  // （`_kProfileSidebarWidth`）と揃える目的で一旦240へ戻したところ、
                  // 劇画UIで一対/広場タブ（`GekigaJointedPair`、横スクロール式で
                  // 折り返せない）が「+」ボタン手前でクリップされ欠けて見える
                  // 不具合が発生したため260へ広げ（250へ微調整後、再度260へ
                  // 戻した）、3画面とも同じ値で揃える。
                  SizedBox(width: 260, child: listPane),
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
  ///
  /// 別の会話に切り替えて戻ってきた時にChatScreenを作り直さない（Firestore
  /// 購読をやり直さない）ため、このセッション中に一度でも開いた会話
  /// （[_visitedConversationKeys]）は全て`IndexedStack`で裏側に保持し続ける
  /// （2026-08-20追加）。会話が削除された場合のみ追跡から取り除く。
  Widget _buildDetailPane(
    List<DirectMessage> directMessages,
    List<Group> groups,
  ) {
    final pending = _selectedPendingScreen;
    if (pending != null) return pending;

    String? activeKey;
    if (_category == _TalksCategory.dm) {
      final selected = _selectedDm;
      final dm = selected == null
          ? null
          : directMessages.firstWhereOrNull((d) => d.dmId == selected.dmId);
      if (dm != null) activeKey = 'dm-${dm.dmId}';
    } else {
      final selected = _selectedGroup;
      final group = selected == null
          ? null
          : groups.firstWhereOrNull((g) => g.groupId == selected.groupId);
      if (group != null) activeKey = 'group-${group.groupId}';
    }
    if (activeKey != null) _visitedConversationKeys.add(activeKey);

    // 選択中の一対・広場が一覧から消えた（削除された）場合、削除前の
    // スナップショットへフォールバックすると既に存在しないmessages/rooms
    // サブコレクションを購読し続けpermission-deniedになるため、訪問履歴
    // からも取り除く（2026-08-13修正、2026-08-20にキャッシュ全体へ拡張）。
    // 併せて`ChatRoomMessageCacheManager`（寄合単位のメッセージ購読キャッシュ、
    // 2026-09-10追加）側のエントリも破棄し、削除済み会話に対する購読が
    // 裏で残り続けないようにする。
    final removedKeys = _visitedConversationKeys.where((key) {
      if (key.startsWith('dm-')) {
        final dmId = key.substring('dm-'.length);
        return !directMessages.any((d) => d.dmId == dmId);
      }
      final groupId = key.substring('group-'.length);
      return !groups.any((g) => g.groupId == groupId);
    }).toList();
    if (removedKeys.isNotEmpty) {
      _visitedConversationKeys.removeAll(removedKeys);
      final cacheManager = ref.read(chatRoomMessageCacheManagerProvider);
      for (final key in removedKeys) {
        final conversationId = key.startsWith('dm-')
            ? key.substring('dm-'.length)
            : key.substring('group-'.length);
        cacheManager.evictConversation(conversationId);
      }
    }

    final visitedList = _visitedConversationKeys.toList();
    final children = <Widget>[
      const _EmptyDetailPlaceholder(),
      for (final key in visitedList)
        if (key.startsWith('dm-'))
          _DmDetailWithRooms(
            key: ValueKey(key),
            currentUser: widget.currentUser,
            dm: directMessages.firstWhere(
              (d) => d.dmId == key.substring('dm-'.length),
            ),
          )
        else
          _GroupDetailWithRooms(
            key: ValueKey(key),
            currentUser: widget.currentUser,
            group: groups.firstWhere(
              (g) => g.groupId == key.substring('group-'.length),
            ),
          ),
    ];
    final activeIndex = activeKey == null
        ? 0
        : 1 + visitedList.indexOf(activeKey);
    return IndexedStack(index: activeIndex, children: children);
  }

  /// 縦表示専用の新レイアウト（`TalksListLayoutStyle.iconSplit`、設定＞語らいで
  /// 選択可能、2026-09-11追加）。左にアイコン一覧（[_buildIconRail]）、右に
  /// 選択中の会話の寄合一覧（[_DmDetailWithRooms]/[_GroupDetailWithRooms]）を
  /// 表示する。
  ///
  /// 横幅が[kIconSplitPeekBreakpoint]以上のタブレット・コンピューター縦表示
  /// では、寄合一覧の右隣にメッセージ画面本体も同時表示する
  /// （`roomListOnly: false`で流用、2026-09-12追加）。この時、アイコン列＋
  /// 寄合一覧をまとめて左にドラッグすると、[_iconSplitCollapse]の進行度に
  /// リアルタイムに追従して畳まれていき（[_CollapsibleWidthPanel]）、
  /// 指を離すと速度／位置に応じて全開（寄合一覧を表示）または全畳み
  /// （既に同時表示中のメッセージ画面本体が全画面表示）のどちらかへ
  /// アニメーションで収束する（既存の`InteractiveSwipeBackTransition`の
  /// 「戻る」ドラッグと対称の設計）。画面遷移は発生させない
  /// （既に埋め込み表示している`DmChatPane`/`GroupChatPane`がそのまま
  /// 全幅になるだけで、別ルートを積まない）。
  ///
  /// [kIconSplitPeekBreakpoint]未満の幅（スマホ縦表示相当）では画面が狭く
  /// メッセージ画面を同時に収められないため、従来通り`roomListOnly: true`の
  /// まま、寄合をタップした時点でフルスクリーンチャットへ遷移する。
  Widget _buildIconSplitPane(
    List<DirectMessage> directMessages,
    List<Group> groups,
    Map<String, ConversationPrefs> prefsById,
    List<FriendRequest> incomingRequests,
    List<FriendRequest> outgoingRequests,
    List<GroupJoinRequest> pendingGroupRequests,
    Set<String> blockedIds,
  ) {
    final iconRail = _buildIconRail(
      directMessages,
      groups,
      prefsById,
      incomingRequests,
      outgoingRequests,
      pendingGroupRequests,
      blockedIds,
    );

    final showPeek = _showIconSplitPeek;

    final Widget detail;
    if (_category == _TalksCategory.dm) {
      final selected = _selectedDm;
      final dm = selected == null
          ? null
          : directMessages.firstWhereOrNull((d) => d.dmId == selected.dmId);
      detail = dm == null
          ? const _EmptyDetailPlaceholder()
          : _DmDetailWithRooms(
              key: ValueKey('icon-split-dm-${dm.dmId}'),
              currentUser: widget.currentUser,
              dm: dm,
              roomListOnly: !showPeek,
              collapseProgress: showPeek ? _iconSplitCollapse : null,
              onExpandTap: showPeek
                  ? () => _animateIconSplitCollapse(1.0)
                  : null,
            );
    } else {
      final selected = _selectedGroup;
      final group = selected == null
          ? null
          : groups.firstWhereOrNull((g) => g.groupId == selected.groupId);
      detail = group == null
          ? const _EmptyDetailPlaceholder()
          : _GroupDetailWithRooms(
              key: ValueKey('icon-split-group-${group.groupId}'),
              currentUser: widget.currentUser,
              group: group,
              roomListOnly: !showPeek,
              collapseProgress: showPeek ? _iconSplitCollapse : null,
              onExpandTap: showPeek
                  ? () => _animateIconSplitCollapse(1.0)
                  : null,
            );
    }

    if (!showPeek) {
      return Row(
        children: [
          SizedBox(width: 112, child: iconRail),
          const VerticalDivider(width: 1),
          Expanded(child: detail),
        ],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _handleIconSplitDragStart,
      onHorizontalDragUpdate: _handleIconSplitDragUpdate,
      onHorizontalDragEnd: _handleIconSplitDragEnd,
      child: Row(
        children: [
          _CollapsibleWidthPanel(
            progress: _iconSplitCollapse,
            width: 112,
            child: iconRail,
          ),
          _CollapsibleDivider(progress: _iconSplitCollapse),
          Expanded(child: detail),
        ],
      ),
    );
  }

  /// [_buildIconSplitPane]の左側ペイン。一対/広場の切り替えは[_CategoryTab]を
  /// そのまま使い、本体は[_buildDirectMessages]/[_buildGroups]と同じソート・
  /// ピン留めロジック（[_applyDmSortOrder]/[_applyGroupSortOrder]/
  /// [_sortedByPin]）を使い回した上で、通常のリストタイルの代わりに
  /// コンパクトなアイコンタイル（[_DirectMessageIconTile]/[_GroupIconTile]）を
  /// 並べる。友達申請・広場参加リクエストは幅の制約上アイコン化せず、
  /// 縦表示の標準レイアウトと同じ`isSplit: false`挙動（タップでフルスクリーン
  /// 遷移）のタイルをそのまま流用する。
  ///
  /// 検索・並べ替え（2026-09-12追加、それまではこのレイアウトには無かった）:
  /// 並べ替えは標準レイアウトと同じ[_buildSortButton]をそのままアイコンボタンで
  /// 並べる。検索は112px幅にタブと検索欄を同時に置けないため、検索アイコンの
  /// タップで[_iconRailSearchOpen]を切り替え、タブ表示と標準レイアウトの
  /// [_buildSearchField]を差し替える形にした（一対・広場を横断する標準の
  /// [_buildSearchResults]とは異なり、この列では現在のタブ内で
  /// [_DirectMessageIconTile]/[_GroupIconTile]を絞り込むだけに留めている）。
  ///
  /// ヘッダー（切り替えピル＋検索・並べ替え・＋ボタン＋Divider）は固定表示の
  /// まま、本体のタイル一覧だけを標準レイアウト（[_categoryPageController]
  /// 参照）と同じ`PageView`にして、このアイコン列の幅の中だけで一対⇄広場を
  /// 横スワイプ切り替えできるようにする（2026-09-11追加。右隣の寄合一覧側は
  /// 項目4の別のスワイプ挙動を持つため、`VerticalDivider`の左側に閉じる
  /// 必要がある）。この列は112px幅しか無く、タブ（一対/広場ピル）・検索・
  /// 並べ替え・＋ボタンのいずれも横並びにすると文字やボタンが収まりきらず
  /// オーバーフローするため、画面の向き（縦表示/横表示）に関わらず**常に
  /// 縦積み**にする（2026-09-11追加時は縦表示時のみ縦積みだったが、
  /// 2026-09-12にタブレット横表示でも縦積みのままにする方針へ変更し、
  /// 向き判定自体を廃止した）。劇画UIではその縦積みに合わせて
  /// [GekigaJointedTileList]（既定で縦積み対応・`axis`で横積みも可）で
  /// 箱枠を描く（標準レイアウトのヘッダーが使う[GekigaJointedPair]は横並び
  /// 2個専用のため、縦積みにも対応できるこちらを使う）。
  Widget _buildIconRail(
    List<DirectMessage> directMessages,
    List<Group> groups,
    Map<String, ConversationPrefs> prefsById,
    List<FriendRequest> incomingRequests,
    List<FriendRequest> outgoingRequests,
    List<GroupJoinRequest> pendingGroupRequests,
    Set<String> blockedIds,
  ) {
    final vocab = ref.watch(vocabularyProvider);
    final strings = ref.watch(appStringsProvider);
    final sortOrder = ref.watch(conversationSortOrderProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    // 検索結果は一対・広場・メッセージを横断する共通の[TalksSearchResultsView]
    // （`showSearchResults`側）で表示するため、ここでは非検索時の一覧
    // （`buildCategoryTiles`）にクエリでの絞り込みを持たせない
    // （2026-09-12変更、以前はこの列だけ現在のタブ内フィルタに留めていた）。
    final searchQuery = _iconRailSearchOpen
        ? _searchController.text.trim()
        : '';
    final showSearchResults = searchQuery.isNotEmpty;

    final dmTab = _CategoryTab(
      label: vocab.dm,
      count: directMessages.length,
      selected: _category == _TalksCategory.dm,
      onTap: () => _setCategory(_TalksCategory.dm),
    );
    final groupTab = _CategoryTab(
      label: vocab.plaza,
      count: groups.length,
      selected: _category == _TalksCategory.group,
      onTap: () => _setCategory(_TalksCategory.group),
    );

    final tabs = isGekiga
        ? GekigaJointedTileList(
            axis: Axis.vertical,
            seeds: [vocab.dm.hashCode, vocab.plaza.hashCode],
            selectedFlags: [
              _category == _TalksCategory.dm,
              _category == _TalksCategory.group,
            ],
            children: [dmTab, groupTab],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [dmTab, const SizedBox(height: 4), groupTab],
          );

    Widget buildCategoryTiles(_TalksCategory category) {
      final tiles = <Widget>[];
      if (category == _TalksCategory.dm) {
        final visibleDms = directMessages
            .where(
              (dm) => !blockedIds.contains(
                dm.otherUserId(widget.currentUser.userId),
              ),
            )
            .toList();
        final orderedDms = _applyDmSortOrder(visibleDms, sortOrder, prefsById);
        final sortedDms = _sortedByPin(orderedDms, prefsById, (dm) => dm.dmId);
        tiles.addAll([
          for (final request in incomingRequests)
            _FriendRequestTile(
              currentUserId: widget.currentUser.userId,
              request: request,
              isSplit: false,
              onSelectPending: _selectPendingScreen,
            ),
          for (final request in outgoingRequests)
            _FriendRequestTile(
              currentUserId: widget.currentUser.userId,
              request: request,
              isSplit: false,
              onSelectPending: _selectPendingScreen,
            ),
          for (final dm in sortedDms)
            _DirectMessageIconTile(
              currentUser: widget.currentUser,
              dm: dm,
              unreadCount: prefsById[dm.dmId]?.unreadCount ?? 0,
              selected: _selectedDm?.dmId == dm.dmId,
              onTap: () => _openDirectMessage(dm),
            ),
        ]);
      } else {
        final orderedGroups = _applyGroupSortOrder(
          groups,
          sortOrder,
          prefsById,
        );
        final sortedGroups = _sortedByPin(
          orderedGroups,
          prefsById,
          (g) => g.groupId,
        );
        tiles.addAll([
          for (final request in pendingGroupRequests)
            _PendingGroupJoinRequestTile(
              request: request,
              isSplit: false,
              onSelectPending: _selectPendingScreen,
            ),
          for (final group in sortedGroups)
            _GroupIconTile(
              group: group,
              unreadCount: prefsById[group.groupId]?.unreadCount ?? 0,
              selected: _selectedGroup?.groupId == group.groupId,
              onTap: () => _openGroup(group),
            ),
        ]);
      }
      return ListView(padding: EdgeInsets.zero, children: tiles);
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: _iconRailSearchOpen
                ? _buildSearchField(strings)
                : SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: tabs,
                  ),
          ),
          // 検索・並べ替え・＋（2026-09-12追加、以前はこのレイアウトには
          // 無かった）。112px幅では横並びだとアイコンボタン3つ分の幅が収まらず
          // オーバーフローするため、常に縦並びにする（検索欄とタブを同時に
          // 並べる余白も無いため、検索アイコンのタップで上のタブ表示と
          // 切り替える）。
          Column(
            children: [
              IconButton(
                icon: Icon(_iconRailSearchOpen ? Icons.close : Icons.search),
                tooltip: '',
                // モバイル実機では112px幅のインライン検索結果は窮屈なため、
                // 専用のフルページ検索（`/talks/search`）へ遷移する
                // （2026-09-12追加、requirement 1）。それ以外
                // （コンピューター・タブレット全般）は従来通りこの列内で
                // トグルする。
                onPressed: () {
                  if (isMobileCallPlatform) {
                    ref
                        .read(goRouterProvider)
                        .push('/talks/search', extra: widget.currentUser);
                    return;
                  }
                  setState(() {
                    _iconRailSearchOpen = !_iconRailSearchOpen;
                    if (!_iconRailSearchOpen) {
                      _searchController.clear();
                      _messageSearchDebounce?.cancel();
                      _messageSearchSession.clear();
                      _messageMatches = const [];
                    }
                  });
                },
              ),
              _buildSortButton(strings),
              IconButton(icon: const Icon(Icons.add), onPressed: _showAddMenu),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: showSearchResults
                ? TalksSearchResultsView(
                    sections: computeTalksSearchSections(
                      query: searchQuery,
                      directMessages: directMessages,
                      groups: groups,
                      blockedIds: blockedIds,
                      currentUserId: widget.currentUser.userId,
                      dmLabelResolver: (dm) {
                        final otherUser = ref
                            .watch(
                              watchedUserProvider(
                                dm.otherUserId(widget.currentUser.userId),
                              ),
                            )
                            .value;
                        return dmSearchLabel(
                          otherUser,
                          dm,
                          widget.currentUser.userId,
                        );
                      },
                      messageMatches: _messageMatches,
                    ),
                    dmSectionLabel: vocab.dm,
                    groupSectionLabel: vocab.plaza,
                    messageSectionLabel: strings.talksSearchSectionMessages,
                    noResultsLabel: strings.talksSearchNoResults,
                    isGekiga: isGekiga,
                    padding: EdgeInsets.zero,
                    dmTileBuilder: (context, dm) => _DirectMessageIconTile(
                      currentUser: widget.currentUser,
                      dm: dm,
                      unreadCount: prefsById[dm.dmId]?.unreadCount ?? 0,
                      selected: _selectedDm?.dmId == dm.dmId,
                      onTap: () => _openDirectMessage(dm),
                    ),
                    groupTileBuilder: (context, group) => _GroupIconTile(
                      group: group,
                      unreadCount: prefsById[group.groupId]?.unreadCount ?? 0,
                      selected: _selectedGroup?.groupId == group.groupId,
                      onTap: () => _openGroup(group),
                    ),
                    messageTileBuilder: (context, hit) => MessageSearchHitTile(
                      currentUser: widget.currentUser,
                      hit: hit,
                      compact: true,
                      onTap: () => _openMessageSearchHit(hit),
                    ),
                  )
                : PageView(
                    controller: _categoryPageController,
                    onPageChanged: _handleCategoryPageChanged,
                    children: [
                      buildCategoryTiles(_TalksCategory.dm),
                      buildCategoryTiles(_TalksCategory.group),
                    ],
                  ),
          ),
        ],
      ),
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

    final sortOrder = ref.watch(conversationSortOrderProvider);
    final orderedDms = _applyDmSortOrder(visibleDms, sortOrder, prefsById);
    final sortedDms = _sortedByPin(orderedDms, prefsById, (dm) => dm.dmId);

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
          DirectMessageTile(
            currentUser: widget.currentUser,
            dm: dm,
            pinned: prefsById[dm.dmId]?.pinned ?? false,
            muted: prefsById[dm.dmId]?.notificationsMuted ?? false,
            unreadCount: prefsById[dm.dmId]?.unreadCount ?? 0,
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
      // 選択中タイルの塗り潰し（selectedTileColor）がカラム間の
      // VerticalDividerに接して重なって見えないよう左右に余白を持たせる
      // （2026-08-12追加、settings_tab.dart/profile_tab.dartの一覧と
      // 同じ手法）。
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
          DirectMessageTile(
            currentUser: widget.currentUser,
            dm: dm,
            pinned: prefsById[dm.dmId]?.pinned ?? false,
            muted: prefsById[dm.dmId]?.notificationsMuted ?? false,
            unreadCount: prefsById[dm.dmId]?.unreadCount ?? 0,
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
    final sortOrder = ref.watch(conversationSortOrderProvider);
    final orderedGroups = _applyGroupSortOrder(groups, sortOrder, prefsById);
    final sortedGroups = _sortedByPin(
      orderedGroups,
      prefsById,
      (g) => g.groupId,
    );

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
          GroupTile(
            currentUserId: widget.currentUser.userId,
            group: group,
            pinned: prefsById[group.groupId]?.pinned ?? false,
            muted: prefsById[group.groupId]?.notificationsMuted ?? false,
            unreadCount: prefsById[group.groupId]?.unreadCount ?? 0,
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
      // 選択中タイルの塗り潰し（selectedTileColor）がカラム間の
      // VerticalDividerに接して重なって見えないよう左右に余白を持たせる
      // （2026-08-12追加、settings_tab.dart/profile_tab.dartの一覧と
      // 同じ手法）。
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final request in pendingRequests)
          _PendingGroupJoinRequestTile(
            request: request,
            isSplit: _isSplit,
            onSelectPending: _selectPendingScreen,
          ),
        for (final group in sortedGroups)
          GroupTile(
            currentUserId: widget.currentUser.userId,
            group: group,
            pinned: prefsById[group.groupId]?.pinned ?? false,
            muted: prefsById[group.groupId]?.notificationsMuted ?? false,
            unreadCount: prefsById[group.groupId]?.unreadCount ?? 0,
            selected: _isSplit && _selectedGroup?.groupId == group.groupId,
            onTap: () => _openGroup(group),
          ),
      ],
    );
  }

  /// 一対/広場切り替えタブの真下に置く検索欄（2026-08-30追加）。
  /// 語らい一覧の並べ替え順を選ぶボタン（検索欄の右隣、2026-09-02追加）。
  /// ピン留めは並べ替え順に関わらず常に最優先で表示され、この設定は
  /// ピン留め内・ピン留め外それぞれの並び順のみを決める。
  Widget _buildSortButton(Strings strings) {
    final current = ref.watch(conversationSortOrderProvider);
    return PopupMenuButton<ConversationSortOrder>(
      icon: const Icon(Icons.sort),
      tooltip: '',
      onSelected: (order) =>
          ref.read(conversationSortOrderProvider.notifier).setOrder(order),
      itemBuilder: (context) => [
        for (final order in ConversationSortOrder.values)
          PopupMenuItem(
            value: order,
            child: Row(
              children: [
                Icon(
                  Icons.check,
                  size: 18,
                  color: order == current ? null : Colors.transparent,
                ),
                const SizedBox(width: 8),
                Text(_sortOrderLabel(strings, order)),
              ],
            ),
          ),
      ],
    );
  }

  String _sortOrderLabel(Strings strings, ConversationSortOrder order) {
    switch (order) {
      case ConversationSortOrder.recent:
        return strings.conversationSortRecent;
      case ConversationSortOrder.kana:
        return strings.conversationSortKana;
      case ConversationSortOrder.unreadFirst:
        return strings.conversationSortUnreadFirst;
    }
  }

  Widget _buildSearchField(Strings strings) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final hasQuery = _searchController.text.isNotEmpty;
    Widget? clearButton(Color? color) {
      if (!hasQuery) return null;
      return IconButton(
        icon: Icon(Icons.clear, color: color),
        onPressed: () => setState(() {
          _searchController.clear();
          _messageSearchDebounce?.cancel();
          _messageSearchSession.clear();
          _messageMatches = const [];
        }),
      );
    }

    switch (uiStyle) {
      case AppUiStyle.gekiga:
        return GekigaTextField(
          controller: _searchController,
          hintText: strings.talksSearchHint,
          prefixIcon: const Icon(Icons.search, color: GekigaColors.onPanel),
          suffixIcon: clearButton(GekigaColors.onPanel),
          onChanged: (_) => _onSearchTextChanged(),
        );
      case AppUiStyle.glass:
        // ガラスUIのすりガラス外枠（GlassSurface）の中に、枠・塗り無しの
        // 素のTextFieldを重ねる（`chat_screen.dart`の入力欄と同じ構成）。
        return GlassSurface(
          variant: GlassVariant.card,
          borderRadius: BorderRadius.circular(24),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              hintText: strings.talksSearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: clearButton(null),
            ),
            onChanged: (_) => _onSearchTextChanged(),
          ),
        );
      case AppUiStyle.flat:
        return TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: strings.talksSearchHint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: clearButton(null),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => _onSearchTextChanged(),
        );
    }
  }

  /// 検索欄に入力がある間、一対/広場/メッセージ内容の3区分でまとめて表示する
  /// （2026-08-30追加、2026-09-12にメッセージ内容検索・3区分表示へ拡張）。
  /// フレンド申請・広場参加リクエストは「語らい」そのものではないため対象外。
  Widget _buildSearchResults(
    String query,
    List<DirectMessage> directMessages,
    List<Group> groups,
    Map<String, ConversationPrefs> prefsById,
    Set<String> blockedIds,
    Strings strings,
  ) {
    final vocab = ref.watch(vocabularyProvider);
    final sections = computeTalksSearchSections(
      query: query,
      directMessages: directMessages,
      groups: groups,
      blockedIds: blockedIds,
      currentUserId: widget.currentUser.userId,
      dmLabelResolver: (dm) {
        final otherUser = ref
            .watch(
              watchedUserProvider(dm.otherUserId(widget.currentUser.userId)),
            )
            .value;
        return dmSearchLabel(otherUser, dm, widget.currentUser.userId);
      },
      messageMatches: _messageMatches,
    );

    return TalksSearchResultsView(
      sections: sections,
      dmSectionLabel: vocab.dm,
      groupSectionLabel: vocab.plaza,
      messageSectionLabel: strings.talksSearchSectionMessages,
      noResultsLabel: strings.talksSearchNoResults,
      isGekiga: ref.watch(appUiStyleProvider) == AppUiStyle.gekiga,
      dmTileBuilder: (context, dm) => DirectMessageTile(
        currentUser: widget.currentUser,
        dm: dm,
        pinned: prefsById[dm.dmId]?.pinned ?? false,
        muted: prefsById[dm.dmId]?.notificationsMuted ?? false,
        unreadCount: prefsById[dm.dmId]?.unreadCount ?? 0,
        selected: _isSplit && _selectedDm?.dmId == dm.dmId,
        onTap: () {
          // 検索結果は一対・広場を横断して表示するため、タップした種類
          // に`_category`を合わせてから開く（合わせないと`_buildDetailPane`
          // が表示中タブ側の選択状態しか見ず、分割表示のペインが
          // 切り替わらない、2026-08-30発覚・修正）。
          setState(() => _category = _TalksCategory.dm);
          _openDirectMessage(dm);
        },
      ),
      groupTileBuilder: (context, group) => GroupTile(
        currentUserId: widget.currentUser.userId,
        group: group,
        pinned: prefsById[group.groupId]?.pinned ?? false,
        muted: prefsById[group.groupId]?.notificationsMuted ?? false,
        unreadCount: prefsById[group.groupId]?.unreadCount ?? 0,
        selected: _isSplit && _selectedGroup?.groupId == group.groupId,
        onTap: () {
          setState(() => _category = _TalksCategory.group);
          _openGroup(group);
        },
      ),
      messageTileBuilder: (context, hit) => MessageSearchHitTile(
        currentUser: widget.currentUser,
        hit: hit,
        onTap: () => _openMessageSearchHit(hit),
      ),
    );
  }

  /// [ConversationSortOrder]に応じて一対の一覧を並べ替える（ピン留めの
  /// 優先適用は呼び出し側の[_sortedByPin]が別途行う、2026-09-02追加）。
  /// `recent`はリポジトリのstreamが既に`lastMessageAt`降順で返しているため
  /// 何もしない（`DirectMessageRepository.watchDirectMessages`参照）。
  List<DirectMessage> _applyDmSortOrder(
    List<DirectMessage> dms,
    ConversationSortOrder order,
    Map<String, ConversationPrefs> prefsById,
  ) {
    switch (order) {
      case ConversationSortOrder.recent:
        return dms;
      case ConversationSortOrder.kana:
        // 検索機能と同じ`dmSearchLabel`（呼び名優先、無ければ@RhingID）を
        // 比較キーに使う。ソート中に何度も同じ値を計算しないよう先に
        // dmId→ラベルのマップを作る。
        final labelByDmId = <String, String>{
          for (final dm in dms)
            dm.dmId: dmSearchLabel(
              ref
                  .watch(
                    watchedUserProvider(
                      dm.otherUserId(widget.currentUser.userId),
                    ),
                  )
                  .value,
              dm,
              widget.currentUser.userId,
            ),
        };
        return [...dms]..sort(
          (a, b) => compareKana(labelByDmId[a.dmId]!, labelByDmId[b.dmId]!),
        );
      case ConversationSortOrder.unreadFirst:
        return [...dms]..sort((a, b) {
          final unreadDiff =
              (_isDmUnread(b, prefsById) ? 1 : 0) -
              (_isDmUnread(a, prefsById) ? 1 : 0);
          if (unreadDiff != 0) return unreadDiff;
          return (b.lastMessageAt?.millisecondsSinceEpoch ?? 0).compareTo(
            a.lastMessageAt?.millisecondsSinceEpoch ?? 0,
          );
        });
    }
  }

  /// 相手が送った直近メッセージを、自分がまだ既読にしていないか
  /// （2026-09-02追加。未読管理の仕組み自体を持たないため、
  /// `DirectMessage.lastMessageSenderId`と`ConversationPrefs.lastReadAt`の
  /// 2フィールド比較だけで近似する。厳密な未読件数管理ではない）。
  bool _isDmUnread(DirectMessage dm, Map<String, ConversationPrefs> prefsById) {
    final lastMessageAt = dm.lastMessageAt;
    if (lastMessageAt == null) return false;
    if (dm.lastMessageSenderId == null ||
        dm.lastMessageSenderId == widget.currentUser.userId) {
      return false;
    }
    final lastReadAt = prefsById[dm.dmId]?.lastReadAt;
    if (lastReadAt == null) return true;
    return lastReadAt.compareTo(lastMessageAt) < 0;
  }

  /// [_applyDmSortOrder]の広場版。
  List<Group> _applyGroupSortOrder(
    List<Group> groups,
    ConversationSortOrder order,
    Map<String, ConversationPrefs> prefsById,
  ) {
    switch (order) {
      case ConversationSortOrder.recent:
        return groups;
      case ConversationSortOrder.kana:
        return [...groups]..sort((a, b) => compareKana(a.name, b.name));
      case ConversationSortOrder.unreadFirst:
        return [...groups]..sort((a, b) {
          final unreadDiff =
              (_isGroupUnread(b, prefsById) ? 1 : 0) -
              (_isGroupUnread(a, prefsById) ? 1 : 0);
          if (unreadDiff != 0) return unreadDiff;
          return (b.lastMessageAt?.millisecondsSinceEpoch ?? 0).compareTo(
            a.lastMessageAt?.millisecondsSinceEpoch ?? 0,
          );
        });
    }
  }

  /// [_isDmUnread]の広場版。
  bool _isGroupUnread(Group group, Map<String, ConversationPrefs> prefsById) {
    final lastMessageAt = group.lastMessageAt;
    if (lastMessageAt == null) return false;
    if (group.lastMessageSenderId == null ||
        group.lastMessageSenderId == widget.currentUser.userId) {
      return false;
    }
    final lastReadAt = prefsById[group.groupId]?.lastReadAt;
    if (lastReadAt == null) return true;
    return lastReadAt.compareTo(lastMessageAt) < 0;
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
            // 縦幅・フォントサイズをフラットスタイル側（vertical:6,
            // fontSize:16）に揃える（2026-08-04変更）。横方向だけは、
            // フラット側に無いジグザグ枠の線に文字が重ならないよう
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
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final background = selected ? colorScheme.primary : colorScheme.surface;
    // ガラスUIは選択・非選択で文字色を変えない（背景の塗りだけで選択状態を
    // 表す）。それ以外のスタイルは従来通り選択中に反転させる。
    final foreground = isGlass
        ? colorScheme.onSurfaceVariant
        : (selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant);

    final content = Padding(
      // 劇画側（上の分岐、vertical:6）と同じ「ラベルと件数を1つの
      // Textにまとめる」構成に揃え、独立した件数バッジ分の余白を
      // 無くすことでチップ1つあたりの幅を縮めている（2026-08-12
      // 変更。以前は件数を別`Container`の丸バッジにしていたが、
      // 幅が増えて狭い画面で「一対/広場」チップが1行に収まらず
      // 折り返される不具合があった）。横幅（14→8）・フォントサイズ
      // （16→13）もさらに詰め、英語表示（"Private"/"Plaza"は日本語の
      // 「一対」「広場」より幅を取る）でも横スクロール無しで260px幅の
      // サイドバーに収まるようにした（2026-08-27変更）。
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        '$label $count',
        style: TextStyle(
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: foreground,
          fontSize: 13,
        ),
      ),
    );

    if (isGlass) {
      return GlassSurface(
        variant: GlassVariant.card,
        borderRadius: BorderRadius.circular(20),
        accentColorOverride: selected ? colorScheme.primary : null,
        child: Material(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.45)
              : Colors.transparent,
          child: InkWell(onTap: onTap, child: content),
        ),
      );
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: content,
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
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
              // 承認前はdirectMessagesドキュメント自体が存在せず実データの
              // 寄合は持てない（firestore.rulesで承認後の作成のみ許可）ため、
              // 承認後に必ずできる「メイン」1件だけの寄合一覧を模した
              // プレースホルダーを、他の（承認済みの）語らいと同じ3カラム
              // 構成で見せる（選択・追加はできない、2026-08-12追加）。
              onSelectPending(
                Row(
                  children: [
                    SizedBox(
                      width: 220,
                      child: RoomListPane(
                        conversationName: titleText,
                        rooms: const [(roomId: 'pending-main', name: 'メイン')],
                        selectedRoomId: 'pending-main',
                        onSelectRoom: (_) {},
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: screen),
                  ],
                ),
              );
            } else {
              // 承認待ち画面は常にメッセージが空（吹き出しが無い＝全面が
              // 余白）で、通常の語らいのように吹き出し上の右スワイプで戻る
              // 仕組み（`_MessageInteractionsState`の`InteractiveSwipeBackScope`
              // 中継）が機能する余地が無い。通常の一対・広場
              // （app_router.dartの`slideDetailPage`）と同じ、指追従の右スワイプ
              // 戻る＋画面右外からのスライドインを`slideBackRoute`で適用する
              // （2026-08-12追加、2026-09-12にインタラクティブなスライドへ変更）。
              Navigator.of(
                context,
              ).push(slideBackRoute<void>(builder: (context) => screen));
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
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
            // _FriendRequestTileと同じ理由（吹き出しが無く
            // InteractiveSwipeBackScope経由の戻る中継が機能しないため、
            // slideBackRouteで画面全体をラップする、2026-08-12追加、
            // 2026-09-12にインタラクティブなスライドへ変更）。
            Navigator.of(
              context,
            ).push(slideBackRoute<void>(builder: (context) => screen));
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

/// 一対の相手の呼び名（無ければ@RhingID、`truncateName`適用前）。
/// [DirectMessageTile]の表示ラベルと`_TalksTabState._buildSearchResults`の
/// 検索対象ラベルの計算がズレないよう共通化する（2026-08-30追加）。
String dmSearchLabel(
  AppUser? otherUser,
  DirectMessage dm,
  String currentUserId,
) {
  final nickname = otherUser?.effectiveNicknameFor(dm.dmId)?.text;
  return (nickname?.isNotEmpty ?? false)
      ? nickname!
      : '@${dm.otherRhingId(currentUserId)}';
}

/// 語らい一覧の最新メッセージプレビュー文字列。テキスト/通話サマリーは
/// 送信時に切り詰め済みの本文（[DirectMessage.lastMessagePreview]/
/// [Group.lastMessagePreview]）をそのまま使い、画像/動画/ファイル/
/// スタンプはロケール依存のためUI側でラベルを組み立てる（2026-09-02追加）。
/// メッセージが1件も無い会話は`contentType`がnullで、プレビュー自体を
/// 出さない。
String? _conversationPreviewLabel(
  Strings strings,
  Vocabulary vocabulary,
  String? contentType,
  String? textPreview,
) {
  switch (contentType) {
    case null:
      return null;
    case 'text':
    case 'call':
      return textPreview;
    case 'image':
      return strings.talksListPreviewImage;
    case 'video':
      return strings.talksListPreviewVideo;
    case 'file':
      return strings.talksListPreviewFile;
    case 'sticker':
      return '[${vocabulary.sticker}]';
    default:
      return textPreview;
  }
}

class DirectMessageTile extends ConsumerWidget {
  const DirectMessageTile({
    required this.currentUser,
    required this.dm,
    required this.pinned,
    required this.muted,
    required this.unreadCount,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  final AppUser currentUser;
  final DirectMessage dm;
  final bool pinned;
  final bool muted;
  final int unreadCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otherUserId = dm.otherUserId(currentUser.userId);
    final otherUser = ref.watch(watchedUserProvider(otherUserId)).value;
    final label = dmSearchLabel(otherUser, dm, currentUser.userId);
    final iconUrl = otherUser?.effectiveIconFor(dm.dmId)?.url;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final colorScheme = Theme.of(context).colorScheme;
    final previewLabel = _conversationPreviewLabel(
      ref.watch(appStringsProvider),
      ref.watch(vocabularyProvider),
      dm.lastMessageContentType,
      dm.lastMessagePreview,
    );

    final leadingWidget = CircleAvatar(
      backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      child: iconUrl == null ? const Icon(Icons.person) : null,
    );
    final subtitleWidget = previewLabel == null
        ? null
        : Text(previewLabel, maxLines: 1, overflow: TextOverflow.ellipsis);
    final trailingWidget = _ConversationTrailing(
      pinned: pinned,
      muted: muted,
      lastMessageAt: dm.lastMessageAt?.toDate(),
      unreadCount: unreadCount,
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
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: subtitleWidget,
          trailing: trailingWidget,
          onTap: onTap,
        ),
      );
    }

    if (isGlass) {
      // 選択・非選択で文字色は変えない（背景の塗りだけで選択状態を表す）。
      return _ConversationGestures(
        conversationId: dm.dmId,
        userId: currentUser.userId,
        pinned: pinned,
        muted: muted,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: GlassSurface(
            variant: GlassVariant.card,
            borderRadius: BorderRadius.circular(12),
            accentColorOverride: selected ? colorScheme.primary : null,
            child: Material(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.45)
                  : Colors.transparent,
              child: ListTile(
                iconColor: colorScheme.onSurfaceVariant,
                textColor: colorScheme.onSurfaceVariant,
                leading: leadingWidget,
                title: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: subtitleWidget,
                trailing: trailingWidget,
                onTap: onTap,
              ),
            ),
          ),
        ),
      );
    }

    return _ConversationGestures(
      conversationId: dm.dmId,
      userId: currentUser.userId,
      pinned: pinned,
      muted: muted,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: selected,
        selectedTileColor: colorScheme.primary,
        selectedColor: colorScheme.onPrimary,
        leading: leadingWidget,
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitleWidget,
        trailing: trailingWidget,
        onTap: onTap,
      ),
    );
  }
}

class GroupTile extends ConsumerWidget {
  const GroupTile({
    required this.currentUserId,
    required this.group,
    required this.pinned,
    required this.muted,
    required this.unreadCount,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  final String currentUserId;
  final Group group;
  final bool pinned;
  final bool muted;
  final int unreadCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconUrl = group.profileCard?.iconUrl;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = group.name;
    final previewLabel = _conversationPreviewLabel(
      ref.watch(appStringsProvider),
      ref.watch(vocabularyProvider),
      group.lastMessageContentType,
      group.lastMessagePreview,
    );

    final leadingWidget = CircleAvatar(
      backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      child: iconUrl == null ? const Icon(Icons.groups) : null,
    );
    final subtitleWidget = previewLabel == null
        ? null
        : Text(previewLabel, maxLines: 1, overflow: TextOverflow.ellipsis);
    final trailingWidget = _ConversationTrailing(
      pinned: pinned,
      muted: muted,
      lastMessageAt: group.lastMessageAt?.toDate(),
      unreadCount: unreadCount,
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
          title: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: subtitleWidget,
          trailing: trailingWidget,
          onTap: onTap,
        ),
      );
    }

    if (isGlass) {
      // 選択・非選択で文字色は変えない（背景の塗りだけで選択状態を表す）。
      return _ConversationGestures(
        conversationId: group.groupId,
        userId: currentUserId,
        pinned: pinned,
        muted: muted,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: GlassSurface(
            variant: GlassVariant.card,
            borderRadius: BorderRadius.circular(12),
            accentColorOverride: selected ? colorScheme.primary : null,
            child: Material(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.45)
                  : Colors.transparent,
              child: ListTile(
                iconColor: colorScheme.onSurfaceVariant,
                textColor: colorScheme.onSurfaceVariant,
                leading: leadingWidget,
                title: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: subtitleWidget,
                trailing: trailingWidget,
                onTap: onTap,
              ),
            ),
          ),
        ),
      );
    }

    return _ConversationGestures(
      conversationId: group.groupId,
      userId: currentUserId,
      pinned: pinned,
      muted: muted,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: selected,
        selectedTileColor: colorScheme.primary,
        selectedColor: colorScheme.onPrimary,
        leading: leadingWidget,
        title: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitleWidget,
        trailing: trailingWidget,
        onTap: onTap,
      ),
    );
  }
}

/// [_buildIconRail]の一対タイル（2026-09-11追加）。データの取得は
/// [DirectMessageTile]と同じ（相手のアイコン・呼び名）だが、表示は
/// アイコン＋名前のコンパクトな[_ConversationIconTile]に差し替えている。
class _DirectMessageIconTile extends ConsumerWidget {
  const _DirectMessageIconTile({
    required this.currentUser,
    required this.dm,
    required this.unreadCount,
    required this.selected,
    required this.onTap,
  });

  final AppUser currentUser;
  final DirectMessage dm;
  final int unreadCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otherUserId = dm.otherUserId(currentUser.userId);
    final otherUser = ref.watch(watchedUserProvider(otherUserId)).value;
    final label = dmSearchLabel(otherUser, dm, currentUser.userId);
    final iconUrl = otherUser?.effectiveIconFor(dm.dmId)?.url;
    return _ConversationIconTile(
      avatar: CircleAvatar(
        backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        child: iconUrl == null ? const Icon(Icons.person) : null,
      ),
      label: label,
      unreadCount: unreadCount,
      selected: selected,
      onTap: onTap,
    );
  }
}

/// [_buildIconRail]の広場タイル（2026-09-11追加）。[_DirectMessageIconTile]と
/// 同じ構成の広場版。
class _GroupIconTile extends StatelessWidget {
  const _GroupIconTile({
    required this.group,
    required this.unreadCount,
    required this.selected,
    required this.onTap,
  });

  final Group group;
  final int unreadCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconUrl = group.profileCard?.iconUrl;
    return _ConversationIconTile(
      avatar: CircleAvatar(
        backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        child: iconUrl == null ? const Icon(Icons.groups) : null,
      ),
      label: group.name,
      unreadCount: unreadCount,
      selected: selected,
      onTap: onTap,
    );
  }
}

/// [_buildIconRail]用の汎用コンパクトタイル（アイコン＋名前を小さく＋未読
/// バッジ、2026-09-11追加）。UIスタイル（劇画/ガラス/フラット）ごとの
/// 専用デザインは持たず、`Theme.of(context).colorScheme`（3スタイルとも
/// テーマ側で調整済み）にそのまま追従する簡易実装。
class _ConversationIconTile extends StatelessWidget {
  const _ConversationIconTile({
    required this.avatar,
    required this.label,
    required this.unreadCount,
    required this.selected,
    required this.onTap,
  });

  final Widget avatar;
  final String label;
  final int unreadCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary.withValues(alpha: 0.18) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                avatar,
                if (unreadCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: BoxDecoration(
                        // CLAUDE.mdの配色方針に合わせ、`colorScheme.error`
                        // ではなく実際にコントラストが確保できる固定の濃い赤
                        // を使う。
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ピン留め・通知オフのアイコン、最終メッセージ時刻、未読件数バッジをまとめた
/// タイルのtrailing（2026-09-02追加、以前は`_ConversationIndicators`という
/// 名前でピン留め/通知オフアイコンのみを担っていたが、責務が増えたため改称）。
class _ConversationTrailing extends ConsumerWidget {
  const _ConversationTrailing({
    required this.pinned,
    required this.muted,
    required this.lastMessageAt,
    required this.unreadCount,
  });

  final bool pinned;
  final bool muted;
  final DateTime? lastMessageAt;
  final int unreadCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final timeFormat = ref.watch(messageTimeFormatProvider);
    final lastMessageAt = this.lastMessageAt;
    final timeLabel = lastMessageAt == null
        ? null
        : formatConversationListTime(lastMessageAt, DateTime.now(), timeFormat);
    final indicatorColor = isGekiga
        ? GekigaColors.onPanel.withValues(alpha: 0.75)
        : resolveTertiaryTextColor(context, isGlass: isGlass);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (pinned || muted) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (muted)
                Icon(
                  Icons.notifications_off_outlined,
                  size: 18,
                  color: indicatorColor,
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
          ),
          const SizedBox(height: 4),
        ],
        if (timeLabel != null)
          Text(
            timeLabel,
            style: TextStyle(fontSize: 12, color: indicatorColor),
          ),
        if (unreadCount > 0) ...[
          const SizedBox(height: 4),
          _UnreadBadge(count: unreadCount),
        ],
      ],
    );
  }
}

/// 未読件数バッジ。CLAUDE.mdの配色規約（薄い背景色に白文字禁止）に従い、
/// 濃色のアクセントカラーを背景に使う（2026-09-02追加）。
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          color: colorScheme.onPrimary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 右クリック（デスクトップ、離してからタップで選ぶ従来のメニュー）・
/// 長押し（モバイル、指を離さず滑らせて選ぶドラッグ選択メニュー）で、
/// ピン留め・通知オフのメニューを出す。ドラッグ選択の実装は
/// `chat_screen.dart`の`_MessageBubbleTapAreaState`と同じパターン
/// （2026-09-02、長押しメニューをドラッグ選択方式に統一）。
class _ConversationGestures extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<_ConversationGestures> createState() =>
      _ConversationGesturesState();
}

class _ConversationGesturesState extends ConsumerState<_ConversationGestures> {
  final _highlightIndex = ValueNotifier<int>(-1);
  OverlayEntry? _overlayEntry;
  DragMenuGeometry? _dragMenuGeometry;
  List<({String action, String label})> _dragMenuItems = const [];

  @override
  void dispose() {
    _removeOverlay();
    _highlightIndex.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _dragMenuGeometry = null;
  }

  List<({String action, String label})> _buildMenuItems(Strings strings) {
    return [
      (
        action: 'pin',
        label: widget.pinned
            ? strings.conversationUnpin
            : strings.conversationPin,
      ),
      (
        action: 'mute',
        label: widget.muted
            ? strings.conversationUnmute
            : strings.conversationMute,
      ),
    ];
  }

  Future<void> _handleAction(String? action) async {
    if (action == 'pin') {
      await ref
          .read(conversationPrefsRepositoryProvider)
          .setPinned(
            userId: widget.userId,
            conversationId: widget.conversationId,
            pinned: !widget.pinned,
          );
    } else if (action == 'mute') {
      await ref
          .read(conversationPrefsRepositoryProvider)
          .setNotificationsMuted(
            userId: widget.userId,
            conversationId: widget.conversationId,
            muted: !widget.muted,
          );
    }
  }

  /// 右クリック用、従来通りのクリック選択メニュー。
  Future<void> _openMenu(BuildContext context, Offset position) async {
    final items = _buildMenuItems(ref.read(appStringsProvider));
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        for (final item in items)
          PopupMenuItem(value: item.action, child: Text(item.label)),
      ],
    );
    if (!context.mounted) return;
    await _handleAction(action);
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final items = _buildMenuItems(ref.read(appStringsProvider));
    final colorScheme = Theme.of(context).colorScheme;
    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final screenSize = overlayBox.size;
    final textStyle = Theme.of(context).textTheme.bodyLarge!;
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    const hPad = 16.0;
    var maxLabelWidth = 0.0;
    for (final item in items) {
      final painter = TextPainter(
        text: TextSpan(text: item.label, style: textStyle),
        textDirection: direction,
        textScaler: textScaler,
      )..layout();
      if (painter.width > maxLabelWidth) maxLabelWidth = painter.width;
    }
    final menuWidth = (maxLabelWidth + hPad * 2).clamp(140.0, 280.0);
    final menuHeight = kDragMenuItemHeight * items.length;

    const screenPad = 8.0;
    final left = details.globalPosition.dx.clamp(
      screenPad,
      screenSize.width - menuWidth - screenPad,
    );
    final top = (details.globalPosition.dy - menuHeight - 8).clamp(
      screenPad,
      screenSize.height - menuHeight - screenPad,
    );

    final geometry = DragMenuGeometry(
      left: left,
      top: top,
      width: menuWidth,
      itemCount: items.length,
    );
    _dragMenuItems = items;
    _dragMenuGeometry = geometry;
    _highlightIndex.value = -1;

    _overlayEntry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.transparent)),
          Positioned(
            left: geometry.left,
            top: geometry.top,
            width: geometry.width,
            height: geometry.height,
            child: Material(
              color: colorScheme.surfaceContainer,
              elevation: 3,
              shadowColor: colorScheme.shadow,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              child: ValueListenableBuilder<int>(
                valueListenable: _highlightIndex,
                builder: (_, highlighted, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Container(
                        height: kDragMenuItemHeight,
                        alignment: AlignmentDirectional.centerStart,
                        padding: const EdgeInsets.symmetric(horizontal: hPad),
                        color: i == highlighted
                            ? colorScheme.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        child: Text(
                          items[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle.copyWith(
                            color: i == highlighted
                                ? colorScheme.primary
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final geometry = _dragMenuGeometry;
    if (geometry == null) return;
    _highlightIndex.value = geometry.hitTest(details.globalPosition);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final geometry = _dragMenuGeometry;
    final items = _dragMenuItems;
    _removeOverlay();
    if (geometry == null) return;
    final index = geometry.hitTest(details.globalPosition);
    if (index < 0) return;
    _handleAction(items[index].action);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _openMenu(context, details.globalPosition),
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _removeOverlay,
      child: widget.child,
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
/// 以前はアイコンを中央表示していたが、ユーザー指示により何も表示しない
/// 方針に変更した（2026-08-12）。
class _EmptyDetailPlaceholder extends StatelessWidget {
  const _EmptyDetailPlaceholder();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// [progress]（0=[width]分の全幅表示、1=幅0まで畳む）に応じて、固定幅
/// [width]を持つ[child]を左詰めで畳んでいく共通ウィジェット
/// （[_TalksTabState._buildIconSplitPane]のアイコン列・寄合一覧の両方の
/// 畳み込みアニメーションで使う、2026-09-12追加）。単純に`SizedBox`の幅
/// だけを狭めると内容（テキスト・アイコン）が潰れてレイアウトエラーになる
/// ため、`Align.widthFactor`で「[width]px分描画された[child]のうち、
/// 左からどれだけを表示領域として確保するか」を制御し、`ClipRect`で
/// はみ出た分を切り取る（`child`は常に[width]px固定でレイアウトされる
/// ため、進行度が変わっても内部のレイアウトは崩れない）。
class _CollapsibleWidthPanel extends StatelessWidget {
  const _CollapsibleWidthPanel({
    required this.progress,
    required this.width,
    required this.child,
  });

  final ValueListenable<double> progress;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      child: child,
      builder: (context, value, child) => ClipRect(
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: (1 - value).clamp(0.0, 1.0),
          child: SizedBox(width: width, child: child),
        ),
      ),
    );
  }
}

/// [_CollapsibleWidthPanel]の右隣に置く区切り線。完全に畳み切った
/// （[progress]が1の）時だけ、余分な1px線が残らないよう自身も消える
/// （2026-09-12追加）。
class _CollapsibleDivider extends StatelessWidget {
  const _CollapsibleDivider({required this.progress});

  final ValueListenable<double> progress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, _) => value >= 1
          ? const SizedBox.shrink()
          : const VerticalDivider(width: 1),
    );
  }
}

/// [_DmDetailWithRoomsState]/[_GroupDetailWithRoomsState]で、寄合一覧の右隣に
/// 埋め込んだ[chatPane]（`DmChatPane`/`GroupChatPane`）の上に、「クリックで
/// 全画面化」のオーバーレイを重ねる（2026-09-12追加、以前は寄合一覧側の左
/// ドラッグで全画面化していたが、クリック操作に差し替えた）。
///
/// [collapseProgress]がnull（左右分割表示など畳み込み概念自体が無い場合）
/// なら[chatPane]をそのまま返す。非nullの場合、進行度が1未満（＝まだ
/// プレビュー中、寄合一覧やアイコン列も見えている状態）の間も、タップで
/// [onExpandTap]を呼ぶ透明な`GestureDetector`（`HitTestBehavior.translucent`）
/// を重ねるだけで、配下の[chatPane]自体は塞がない（2026-09-12、当初は
/// `AbsorbPointer`で操作ごと無効化していたが、プレビュー中もメッセージ
/// 一覧のスクロールだけは行えるようにしてほしいとの要望を受けて変更した。
/// `translucent`なのでポインタイベントは[chatPane]側にも届き、縦ドラッグは
/// そちらのスクロール処理がそのまま受け取る。単純なタップは`onTap`にも
/// 渡るため、クリックでの全画面化は従来通り機能する）。進行度が1に達したら
/// （＝全画面化済み）オーバーレイ自体を外し、[chatPane]を素通しで通常通り
/// 操作できるようにする。[chatPane]は`ValueListenableBuilder.child`として
/// 毎フレーム同一インスタンスを渡すため、オーバーレイの有無が切り替わっても
/// チャット本体（Firestore購読を抱えた`State`）は再構築されない。
Widget _buildExpandableChatPane({
  required ValueListenable<double>? collapseProgress,
  required VoidCallback? onExpandTap,
  required Widget chatPane,
}) {
  if (collapseProgress == null) return chatPane;
  return ValueListenableBuilder<double>(
    valueListenable: collapseProgress,
    child: chatPane,
    builder: (context, progress, child) {
      if (progress >= 1) return child!;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onExpandTap,
        child: child,
      );
    },
  );
}

/// [roomOrder]（`Group.roomOrder`/`DirectMessage.roomOrder`、寄合idの並び）
/// に従って[rooms]を並べ替える（2026-09-08追加、寄合一覧サイドバーの
/// 並べ替え機能用）。[roomOrder]に含まれない寄合（新規作成直後・機能追加前
/// の既存データ）は、元の順序（`watchRooms`が返す作成日時順）のまま末尾に
/// 追加する。[roomOrder]内の既に削除済みの寄合idは単に無視される。
List<T> _orderedRooms<T>(
  List<T> rooms,
  List<String> roomOrder,
  String Function(T room) roomId,
) {
  final byId = {for (final r in rooms) roomId(r): r};
  final ordered = [
    for (final id in roomOrder)
      if (byId.containsKey(id)) byId[id]!,
  ];
  final orderedIds = ordered.map(roomId).toSet();
  ordered.addAll(rooms.where((r) => !orderedIds.contains(roomId(r))));
  return ordered;
}

/// 選択中の一対を、寄合一覧サイドバー＋選択中の寄合のChatScreenの2ペイン
/// 構成で表示する。以前は`_TalksTabState`が全会話共通の1つの
/// `_selectedDmRoomId`フィールドで寄合選択を管理していたが、
/// `_TalksTabState._buildDetailPane`が複数会話を同時に`IndexedStack`で
/// 保持するようになった（2026-08-20、語らい切り替えラグの解消）ため、
/// 会話ごとに独立して寄合選択を保持できるよう、この単位を専用の
/// `StatefulWidget`として切り出した。`_TalksTabState`から`dm.dmId`単位の
/// `ValueKey`で構築されるため、そのidの会話が選択され続けている限り
/// このStateごとDmChatPane（＝Firestore購読）も保持され続ける。
class _DmDetailWithRooms extends ConsumerStatefulWidget {
  const _DmDetailWithRooms({
    required this.currentUser,
    required this.dm,
    this.roomListOnly = false,
    this.collapseProgress,
    this.onExpandTap,
    super.key,
  });

  final AppUser currentUser;
  final DirectMessage dm;

  /// trueの場合、チャット本体は埋め込まず寄合一覧のみをペイン全幅で表示し、
  /// 寄合をタップするとフルスクリーンチャットへ遷移する（縦表示のアイコン＋
  /// 寄合一覧レイアウト用、2026-09-11追加。広い画面の左右分割表示では
  /// falseのまま、寄合一覧の右隣にチャット本体を埋め込む従来通りの構成）。
  final bool roomListOnly;

  /// [roomListOnly]がfalseの状態（＝寄合一覧の右隣にチャット本体を同時表示中）
  /// で非nullの場合、寄合一覧を左右にドラッグした進行度に合わせて寄合一覧を
  /// 畳み込み、チャット本体を全幅表示に近づける
  /// （`_TalksTabState._iconSplitCollapse`、タブレット・コンピューター縦表示の
  /// アイコン＋寄合一覧レイアウト用、2026-09-12追加）。広い左右分割表示
  /// （`_isSplit`）側からは渡さず、既定のnullのままにする（あちらは寄合一覧が
  /// 常設サイドバーのため、畳んで全画面化するという概念自体が無い）。
  final ValueListenable<double>? collapseProgress;

  /// [collapseProgress]が非nullの間、まだ畳み切っていない（プレビュー中の）
  /// メッセージ画面をクリックした時に呼ぶ（2026-09-12追加）。寄合一覧を
  /// 左ドラッグで畳む操作は廃止し、クリックでの全画面化に一本化した
  /// （`_TalksTabState._animateIconSplitCollapse(1.0)`を渡す想定）。
  final VoidCallback? onExpandTap;

  @override
  ConsumerState<_DmDetailWithRooms> createState() => _DmDetailWithRoomsState();
}

class _DmDetailWithRoomsState extends ConsumerState<_DmDetailWithRooms> {
  /// 現在表示中の寄合。nullなら[widget.dm]のdefaultRoomIdにフォールバック
  /// する（2026-08-09変更、以前はdefaultRoomId固定だった）。
  String? _selectedRoomId;

  late final Stream<List<DmRoom>> _roomsStream;

  @override
  void initState() {
    super.initState();
    _roomsStream = ref
        .read(directMessageRepositoryProvider)
        .watchRooms(dmId: widget.dm.dmId, userId: widget.currentUser.userId);
  }

  // モバイルのみ全画面の/callへpushする。PCでは全画面ルートを使わず、
  // 通話セッションを直接開始するだけにする（2026-08-19変更）。発信者は
  // 既に分割表示でこの一対を見ているため、以後は`EmbeddedCallPane`が
  // その表示エリア内に埋め込み表示として引き継ぐ。
  Future<void> _startCall(DirectMessage dm, {bool isVideo = false}) async {
    final callRepository = ref.read(callRepositoryProvider);
    final currentUser = widget.currentUser;
    final other = AppUser(
      userId: dm.otherUserId(currentUser.userId),
      rhingId: dm.otherRhingId(currentUser.userId),
    );
    final call = await callRepository.createCall(
      caller: currentUser,
      callee: other,
      dmId: dm.dmId,
      isVideo: isVideo,
    );
    if (isMobileCallPlatform) {
      ref
          .read(goRouterProvider)
          .push(
            '/call',
            extra: CallArgs(
              call: call,
              isCaller: true,
              currentUserId: currentUser.userId,
            ),
          );
      return;
    }
    ref
        .read(activeCallSessionProvider.notifier)
        .startOneToOne(
          call: call,
          isCaller: true,
          callRepository: callRepository,
          directMessageRepository: ref.read(directMessageRepositoryProvider),
        );
  }

  @override
  Widget build(BuildContext context) {
    final dm = widget.dm;
    final currentUser = widget.currentUser;
    final dmRepository = ref.read(directMessageRepositoryProvider);
    final otherUserId = dm.otherUserId(currentUser.userId);
    final otherUser = ref.watch(watchedUserProvider(otherUserId)).value;
    final otherNickname = otherUser?.effectiveNicknameFor(dm.dmId)?.text;
    final conversationName = (otherNickname?.isNotEmpty ?? false)
        ? otherNickname!
        : '@${dm.otherRhingId(currentUser.userId)}';
    return StreamBuilder<List<DmRoom>>(
      stream: _roomsStream,
      builder: (context, snapshot) {
        final rooms = snapshot.data ?? const <DmRoom>[];
        final roomId =
            (_selectedRoomId != null &&
                rooms.any((r) => r.roomId == _selectedRoomId))
            ? _selectedRoomId!
            : (rooms.isNotEmpty ? rooms.first.roomId : dm.defaultRoomId);
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

        // 縦表示のアイコン＋寄合一覧レイアウト（[widget.roomListOnly]）では
        // チャット本体を埋め込む余白が無いため、寄合をタップしたら
        // ローカルの選択状態を切り替えるのではなくフルスクリーンチャットへ
        // 遷移する（既存の`/chat/dm`ルートをそのまま使う、2026-09-11追加）。
        // このレイアウトの寄合一覧では既に寄合を選んで来ているため、遷移先
        // チャット画面の寄合タブバーは重複表示になる→非表示にする
        // （`showRoomTabBar: false`、下の左スワイプでの遷移と共通化）。
        void openRoomFullscreen(String targetRoomId, String targetRoomName) {
          ref
              .read(goRouterProvider)
              .push(
                '/chat/dm',
                extra: DmChatArgs(
                  currentUser: currentUser,
                  dm: dm,
                  roomId: targetRoomId,
                  roomName: targetRoomName,
                  showRoomTabBar: false,
                  enterFromRight: true,
                ),
              );
        }

        final roomListPane = RoomListPane(
          conversationName: conversationName,
          rooms: [
            for (final r in _orderedRooms(rooms, dm.roomOrder, (r) => r.roomId))
              (roomId: r.roomId, name: r.name),
          ],
          selectedRoomId: roomId,
          onSelectRoom: widget.roomListOnly
              ? (room) => openRoomFullscreen(room.roomId, room.name)
              : (room) => setState(() => _selectedRoomId = room.roomId),
          onCreateRoom: (name) =>
              dmRepository.createRoom(dmId: dm.dmId, name: name),
          onReorderRooms: (roomIds) =>
              dmRepository.setRoomOrder(dmId: dm.dmId, roomIds: roomIds),
        );

        if (widget.roomListOnly) {
          // 単一モードの会話はここに辿り着く前（アイコンタップ時点）で
          // 直接フルスクリーン遷移させているため、通常は到達しない防御的な
          // フォールバック。
          if (!dm.roomsEnabled) return const _EmptyDetailPlaceholder();
          // 寄合一覧上で左スワイプすると、現在ハイライトされている
          // （＝色が付いている）寄合を開く（2026-09-11追加）。
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -300) {
                openRoomFullscreen(roomId, roomName);
              }
            },
            child: roomListPane,
          );
        }

        // タブレット・コンピューター縦表示のアイコン＋寄合一覧レイアウトでは、
        // 寄合一覧の右隣にチャット本体を同時表示しつつ、[widget.collapseProgress]
        // の進行度に合わせて寄合一覧を畳めるようにする（2026-09-12追加、
        // ドラッグ検知自体は`_TalksTabState._buildIconSplitPane`側で行う）。
        final collapseProgress = widget.collapseProgress;
        final roomListBox = collapseProgress == null
            ? SizedBox(width: 220, child: roomListPane)
            : _CollapsibleWidthPanel(
                progress: collapseProgress,
                width: 220,
                child: roomListPane,
              );

        return Row(
          children: [
            // 単一モードではサイドバーを出さない（2026-07-29追加、
            // `DirectMessage.roomsEnabled`参照）。寄合を増やす操作は
            // ハンバーガーメニューから行う（`_DmMenuButton`参照）。
            if (dm.roomsEnabled) ...[
              roomListBox,
              if (collapseProgress == null)
                const VerticalDivider(width: 1)
              else
                _CollapsibleDivider(progress: collapseProgress),
            ],
            Expanded(
              child: _buildExpandableChatPane(
                collapseProgress: collapseProgress,
                onExpandTap: widget.onExpandTap,
                chatPane: DmChatPane(
                  key: ValueKey('detail-dm-${dm.dmId}-$roomId'),
                  currentUser: currentUser,
                  dm: dm,
                  roomId: roomId,
                  roomName: roomName,
                  onCallPressed: () => _startCall(dm),
                  onVideoCallPressed: () => _startCall(dm, isVideo: true),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// [_DmDetailWithRooms]と同じ構成・同じ理由の広場版（フォールバックも同様に
/// 一番上の寄合）。寄合の追加・削除はmanageRooms権限を持つメンバーのみ
/// （firestore.rulesで強制、ここではUI上の操作可否も合わせる）。
class _GroupDetailWithRooms extends ConsumerStatefulWidget {
  const _GroupDetailWithRooms({
    required this.currentUser,
    required this.group,
    this.roomListOnly = false,
    this.collapseProgress,
    this.onExpandTap,
    super.key,
  });

  final AppUser currentUser;
  final Group group;

  /// [_DmDetailWithRooms.roomListOnly]と同じ（2026-09-11追加）。
  final bool roomListOnly;

  /// [_DmDetailWithRooms.collapseProgress]と同じ（2026-09-12追加）。
  final ValueListenable<double>? collapseProgress;

  /// [_DmDetailWithRooms.onExpandTap]と同じ（2026-09-12追加）。
  final VoidCallback? onExpandTap;

  @override
  ConsumerState<_GroupDetailWithRooms> createState() =>
      _GroupDetailWithRoomsState();
}

class _GroupDetailWithRoomsState extends ConsumerState<_GroupDetailWithRooms> {
  String? _selectedRoomId;

  late final Stream<List<Room>> _roomsStream;

  @override
  void initState() {
    super.initState();
    _roomsStream = ref
        .read(groupRepositoryProvider)
        .watchRooms(
          groupId: widget.group.groupId,
          userId: widget.currentUser.userId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final currentUser = widget.currentUser;
    final groupRepository = ref.read(groupRepositoryProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final canManageRooms = hasGroupPermission(
      group: group,
      userId: currentUser.userId,
      permission: GroupPermission.manageRooms,
    );
    return StreamBuilder<List<Room>>(
      stream: _roomsStream,
      builder: (context, snapshot) {
        final rooms = snapshot.data ?? const <Room>[];
        final roomId =
            (_selectedRoomId != null &&
                rooms.any((r) => r.roomId == _selectedRoomId))
            ? _selectedRoomId!
            : (rooms.isNotEmpty ? rooms.first.roomId : group.defaultRoomId);
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

        // [_DmDetailWithRooms]と同じ理由（2026-09-11追加）。
        void openRoomFullscreen(String targetRoomId, String targetRoomName) {
          ref
              .read(goRouterProvider)
              .push(
                '/chat/group',
                extra: GroupChatArgs(
                  currentUser: currentUser,
                  group: group,
                  roomId: targetRoomId,
                  roomName: targetRoomName,
                  showRoomTabBar: false,
                  enterFromRight: true,
                ),
              );
        }

        final roomListPane = RoomListPane(
          conversationName: group.name,
          rooms: [
            for (final r in _orderedRooms(
              rooms,
              group.roomOrder,
              (r) => r.roomId,
            ))
              (roomId: r.roomId, name: r.name),
          ],
          selectedRoomId: roomId,
          onSelectRoom: widget.roomListOnly
              ? (room) => openRoomFullscreen(room.roomId, room.name)
              : (room) => setState(() => _selectedRoomId = room.roomId),
          onCreateRoom: canManageRooms
              ? (name) => groupRepository.createRoom(
                  groupId: group.groupId,
                  name: name,
                )
              : null,
          onReorderRooms: canManageRooms
              ? (roomIds) => groupRepository.setRoomOrder(
                  groupId: group.groupId,
                  roomIds: roomIds,
                )
              : null,
          // 全体設定ポップアップ自体は全メンバーが開ける
          // （中の各項目が個別に権限ゲートされる、2026-07-29変更。
          // 以前はcanManageRolesの間だけロール管理を直接開いていた）。
          onOpenGroupSettings: () => showGroupSettingsDialog(
            context,
            currentUser: currentUser,
            group: group,
            isGlass: isGlass,
          ),
        );

        if (widget.roomListOnly) {
          // 単一モードの会話はここに辿り着く前（アイコンタップ時点）で
          // 直接フルスクリーン遷移させているため、通常は到達しない防御的な
          // フォールバック。
          if (!group.roomsEnabled) return const _EmptyDetailPlaceholder();
          // 寄合一覧上で左スワイプすると、現在ハイライトされている
          // （＝色が付いている）寄合を開く（2026-09-11追加）。
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -300) {
                openRoomFullscreen(roomId, roomName);
              }
            },
            child: roomListPane,
          );
        }

        // [_DmDetailWithRoomsState]と同じ理由（2026-09-12追加）。
        final collapseProgress = widget.collapseProgress;
        final roomListBox = collapseProgress == null
            ? SizedBox(width: 220, child: roomListPane)
            : _CollapsibleWidthPanel(
                progress: collapseProgress,
                width: 220,
                child: roomListPane,
              );

        return Row(
          children: [
            // 単一モードではサイドバーを出さない（2026-07-29追加、
            // `Group.roomsEnabled`参照）。「広場自体の設定」・寄合を増やす
            // 操作はハンバーガーメニューから行う（`_GroupMenuButton`参照）。
            if (group.roomsEnabled) ...[
              roomListBox,
              if (collapseProgress == null)
                const VerticalDivider(width: 1)
              else
                _CollapsibleDivider(progress: collapseProgress),
            ],
            Expanded(
              child: _buildExpandableChatPane(
                collapseProgress: collapseProgress,
                onExpandTap: widget.onExpandTap,
                chatPane: GroupChatPane(
                  key: ValueKey('detail-group-${group.groupId}-$roomId'),
                  currentUser: currentUser,
                  group: group,
                  roomId: roomId,
                  roomName: roomName,
                  // このRowは広い分割表示専用で、左側に物理的なサイドバー
                  // （`roomListPane`）が常に存在する（2026-09-11追加、
                  // `hasSidebar`はここでのみtrueにする。他の呼び出し元は
                  // 既定のfalseのまま）。
                  hasSidebar: true,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
