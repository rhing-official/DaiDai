import '../../providers/account_switcher_providers.dart';
import '../account/account_tab.dart';
import '../../theme/motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../utils/community_group.dart';
import '../../widgets/app_dialog.dart';
import '../chat/join_group_screen.dart';
import '../../providers/repository_providers.dart';
import '../../router/back_stack.dart';
import '../../models/app_user.dart';
import '../../models/nav_chip_layout.dart';
import '../../providers/nav_chip_layout_provider.dart';
import '../../providers/home_shell_providers.dart';
import '../../providers/slide_pick_enabled_provider.dart';
import '../../providers/icon_split_mirrored_provider.dart';
import '../../providers/talks_list_layout_style_provider.dart';
import '../../widgets/nav_chip.dart';
import '../../widgets/pane_visibility.dart';
import '../chat/talks_tab.dart';
import '../profile/profile_tab.dart';
import '../settings/settings_tab.dart';

/// サイドバー/下部ナビの切り替えしきい値。Material Design 3の
/// medium windowサイズクラス（600dp）を採用する。
const _kWideLayoutBreakpoint = 600.0;

/// ホーム画面。語らい・身だしなみ・設定の3タブで構成される
/// （2026-07-30、運営タブを廃止し設定タブ内のカテゴリへ統合）。
/// 画面幅に応じて、コンピューターUI（サイドバー）とモバイルUI（下部ナビ）を切り替える。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;

  // 設定・身だしなみのトップの横スワイプなど、外部からタブが切り替わった時の
  // 横スライド（2026-11-02）。`_slideFrom`は滑り出す前のタブ、`_slide`が0→1で進む。
  int? _slideFrom;

  /// 今の切り替えを、横スライドではなくダイアログと同じ現れ方（画面遷移の設定）で
  /// 見せるか（`homeTabAppearRequestProvider`、2026-11-06）。
  bool _appear = false;
  late final AnimationController _slide =
      AnimationController(vsync: this, duration: popSlideDuration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && _slideFrom != null) {
            setState(() {
              _slideFrom = null;
              _appear = false;
            });
          }
        });

  // 横ドラッグ（設定・身だしなみのトップ）に追従するスライド量。画面幅に対する割合で、
  // 右が正（負なら表示順の右隣が左から寄ってくる）。離した後は`_settle`で0か±1へ寄せる。
  double _drag = 0;
  late final AnimationController _settle = AnimationController(vsync: this);
  late final HomeTabDragController _dragController;

  /// 「アカウント」のチップを出すか。保存したアカウントが2つ以上で、縦画面（狭い画面）で、
  /// 設定（端末ごと）でオンの時だけ（2026-11-11）。横表示は、設定を開けば最初からアカウント（切り替え）が開くので
  /// 出さない。
  bool _accountChipShown() =>
      ref.read(accountTabVisibleProvider) &&
      ref.read(navChipLayoutProvider).accountChipEnabled &&
      MediaQuery.sizeOf(context).width < _kWideLayoutBreakpoint;

  /// 今チップを並べる順（論理インデックス）。
  List<int> _displayOrderNow() => visibleNavChipIndexes(
    ref.read(navChipLayoutProvider).order,
    showAccount: _accountChipShown(),
  );

  /// ドラッグの単位はタブ数（画面幅1つ分＝1タブ）。画面幅を超えて引けば2つ以上先へ進める。
  void _onDragDelta(double dx) {
    if (ref.read(backStackControllerProvider).hasOpenOverlay) return;
    _settle.stop();
    final width = MediaQuery.sizeOf(context).width;
    final order = _displayOrderNow();
    final pos = order.indexOf(_selectedIndex);
    final next = (_drag + dx / width).clamp(
      -(order.length - 1 - pos).toDouble(),
      pos.toDouble(),
    );
    setState(() => _drag = next);
  }

  void _onDragEnd(double velocity) {
    if (_drag == 0) return;
    final order = _displayOrderNow();
    final pos = order.indexOf(_selectedIndex);
    final towards = _drag < 0 ? -1.0 : 1.0;
    final flung = velocity * towards > 600;
    // 引いた距離で何タブ進むか。1タブの35%を超えたら次のタブへ、はじいた時は最低1タブ。
    final distance = _drag.abs();
    var steps = distance.floor() + (distance - distance.floor() > 0.35 ? 1 : 0);
    if (flung && steps == 0) steps = 1;
    final targetPos = (pos - towards.toInt() * steps).clamp(
      0,
      order.length - 1,
    );
    final commit = targetPos != pos;
    final from = _drag;
    final target = commit ? -(targetPos - pos).toDouble() : 0.0;
    _settle.duration = popSlideDuration * (target - from).abs().clamp(0.2, 1.0);
    final tween = Tween<double>(begin: from, end: target);
    void tick() => setState(() => _drag = tween.evaluate(_settle));
    _settle
      ..removeListener(tick)
      ..addListener(tick);
    _settle.forward(from: 0).whenComplete(() {
      _settle.removeListener(tick);
      if (!mounted) return;
      setState(() {
        if (commit) _setSelectedIndex(order[targetPos]);
        _drag = 0;
      });
    });
  }

  /// 滑らせた指が乗ったチップのタブへ切り替える（[_ChipStripPickTarget.pick]から）。
  void _pickChip(int? index, {required bool commit}) {
    if (!mounted) return;
    if (index == null || commit) {
      if (_isDragging || _poppedIndexes.isNotEmpty) {
        setState(() {
          _isDragging = false;
          _poppedIndexes = {};
        });
      }
      return;
    }
    setState(() {
      _isDragging = true;
      _poppedIndexes = {index};
      if (index != _selectedIndex) _setSelectedIndex(index);
    });
  }

  // 語らいの部品（一対・広場の切り替えなど）を押した指を、そのままチップ列へ滑らせて
  // タブを切り替えられるようにする登録先（2026-11-05、`ItemPickBridge`）。
  late final _ChipStripPickTarget _chipPickTarget = _ChipStripPickTarget(this);
  bool _stripVertical = false;

  @override
  void initState() {
    super.initState();
    ref.read(itemPickBridgeProvider).register(_chipPickTarget);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeRecommendCommunity(),
    );
    _dragController = ref.read(homeTabDragControllerProvider)
      ..onDelta = _onDragDelta
      ..onEnd = _onDragEnd;
  }

  /// 新規登録した人に、Rhingコミュニティへの参加を1度だけおすすめする（2026-11-11）。
  Future<void> _maybeRecommendCommunity() async {
    if (!mounted || kCommunityGroupId.isEmpty) return;
    if (widget.currentUser.preferences.communityPromptSeen != false) return;
    final userId = widget.currentUser.userId;
    final userRepository = ref.read(userRepositoryProvider);
    // 先に記録しておく（途中で閉じても繰り返さない）。
    await userRepository.updateUserPreference(
      userId,
      'communityPromptSeen',
      true,
    );
    if (!mounted) return;
    final strings = ref.read(appStringsProvider);
    final join = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.settingsCommunity),
        content: Text(strings.communityPromptBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.communityPromptLater),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.communityPromptJoin),
          ),
        ],
      ),
    );
    if (join != true || !mounted) return;
    await showAppDialog<void>(
      context: context,
      builder: (_) => JoinGroupScreen(
        groupId: kCommunityGroupId,
        asDialog: true,
        currentUser: widget.currentUser,
      ),
    );
  }

  @override
  void dispose() {
    ref.read(itemPickBridgeProvider).unregister(_chipPickTarget);
    // 作り直しで新しいStateが先にinitStateされている場合は、そちらのコールバックを消さない。
    if (_dragController.onDelta == _onDragDelta) {
      _dragController
        ..onDelta = null
        ..onEnd = null;
    }
    _settle.dispose();
    _slide.dispose();
    super.dispose();
  }

  AppUser? _cachedTabsUser;
  List<Widget>? _cachedTabs;

  // なぞっている間だけ選択中チップを飛び出させる為のフラグ（2026-07-29追加）。
  // ドラッグ開始でtrue、指を離す/キャンセルでfalseに戻す。
  bool _isDragging = false;

  // なぞっている間、飛び出させるチップのindex集合。指がチップの真上にある
  // 間は1件だけ、チップ同士の隙間の上にある間は前後2件になる
  // （2026-07-29追加）。色（選択中の塗り）は_selectedIndexだけに紐付ける
  // ため、隙間で両方飛び出していても色が付くのは元々選択されていた方のみ。
  Set<int> _poppedIndexes = {};

  // チップ列で始めたタッチを、そのまま項目一覧（設定・身だしなみのトップ）へ滑らせて
  // 選べるようにする状態（2026-11-03、`ItemPickBridge`）。
  final GlobalKey _stripKey = GlobalKey();
  bool _stripTouch = false;
  ItemPickTarget? _pickTarget;
  int? _pickedIndex;

  String? _diagSlideReason;

  /// 診断ログ（debugのみ、2026-11-12。押したまま滑らせて選ぶが効かない原因の切り分け用）。
  /// 状態が変わった時だけ出す。
  void _diagSlide(String reason) {
    if (!kDebugMode || _diagSlideReason == reason) return;
    _diagSlideReason = reason;
    debugPrint('[DIAG-SLIDE] $reason');
  }

  void _onStripPointerDown(Offset position, bool vertical) {
    _diagSlideReason = null;
    if (kDebugMode) {
      debugPrint(
        '[DIAG-SLIDE] down pos=$position overlay='
        '${ref.read(backStackControllerProvider).hasOpenOverlay} '
        'enabled=${ref.read(slidePickEnabledProvider)} vertical=$vertical',
      );
    }
    if (ref.read(backStackControllerProvider).hasOpenOverlay) return;
    _stripTouch = true;
    // 指が項目へ滑っていくとチップのタップが成立しなくなる為、押した時点で選ぶ。
    final order = _displayOrderNow();
    final hit = _hitTestChips(position, vertical, order);
    final hovered = hit.hovered;
    if (hovered != null && hovered != _selectedIndex) {
      setState(() => _setSelectedIndex(hovered));
    }
  }

  void _onStripPointerMove(Offset position) {
    if (!_stripTouch) return;
    final box = _stripKey.currentContext?.findRenderObject();
    final inStrip =
        box is RenderBox &&
        box.attached &&
        (box.localToGlobal(Offset.zero) & box.size).contains(position);
    final bridge = ref.read(itemPickBridgeProvider);
    // 「押したまま滑らせて選ぶ」をオフにしている時は項目へ渡さない（2026-11-05）。
    final enabled = ref.read(slidePickEnabledProvider);
    final target = (inStrip || !enabled) ? null : bridge.targetAt(position);
    final index = target?.indexAt(position);
    _diagSlide(
      'move inStrip=$inStrip enabled=$enabled target=${target != null} '
      'index=$index',
    );
    if (target == null || index == null) {
      _clearPick();
      return;
    }
    if (_pickTarget != target) {
      _pickTarget?.pick(null, commit: false);
      _pickedIndex = null;
    }
    _pickTarget = target;
    if (_pickedIndex != index) {
      _pickedIndex = index;
      target.pick(index, commit: false);
    }
  }

  void _clearPick() {
    if (_pickedIndex != null) _pickTarget?.pick(null, commit: false);
    _pickedIndex = null;
    _pickTarget = null;
  }

  void _onStripPointerEnd({required bool commit}) {
    final target = _pickTarget;
    final index = _pickedIndex;
    _stripTouch = false;
    _pickTarget = null;
    _pickedIndex = null;
    if (target == null || index == null) return;
    target.pick(commit ? index : null, commit: commit);
  }

  // チップの帯を指でなぞっている間、今指が乗っているチップの実際の描画位置を
  // 判定する為に使う（2026-07-29変更、以前はフリック時の速度だけで隣へ
  // 1段階移動する実装だった。指を離すまで連続的に、語らいから設定まで
  // 1回のドラッグで移動出来るようにする為、位置ベースの追従に変更）。
  late final List<GlobalKey> _chipKeys = List.generate(
    HomeTabId.values.length,
    (_) => GlobalKey(),
  );

  /// 各チップの画面上（global座標）での矩形。まだ描画されていないチップは
  /// nullのまま。
  List<Rect?> _chipGlobalRects() => [
    for (final key in _chipKeys)
      switch (key.currentContext?.findRenderObject()) {
        final RenderBox box => box.localToGlobal(Offset.zero) & box.size,
        _ => null,
      },
  ];

  /// [globalPosition]に対して、今どのチップを選択すべきか（`hovered`。
  /// チップの隙間の上にある場合はnull＝選択は変えない）と、飛び出させる
  /// べきチップのindex集合（`popped`。指がチップ真上なら1件、隙間の上なら
  /// 前後2件）を求める。
  ///
  /// [order]は画面に並んでいる順の論理インデックス（縦表示のカスタム並び替え、
  /// 2026-11-01）。「隣同士」はこの表示順で判定し、結果は論理インデックスで返す。
  ({int? hovered, Set<int> popped}) _hitTestChips(
    Offset globalPosition,
    bool vertical,
    List<int> order,
  ) {
    final rects = _chipGlobalRects();
    for (final i in order) {
      final rect = rects[i];
      if (rect != null && rect.contains(globalPosition)) {
        return (hovered: i, popped: {i});
      }
    }
    // どのチップの上でも無い＝隙間。隙間を挟む前後2つのチップを両方
    // 飛び出させる（選択自体は変えない）。
    for (var k = 0; k < order.length - 1; k++) {
      final i = order[k];
      final a = rects[order[k]];
      final b = rects[order[k + 1]];
      if (a == null || b == null) continue;
      final pastA = vertical
          ? globalPosition.dy >= a.bottom
          : globalPosition.dx >= a.right;
      final beforeB = vertical
          ? globalPosition.dy <= b.top
          : globalPosition.dx <= b.left;
      if (pastA && beforeB) {
        return (hovered: null, popped: {i, order[k + 1]});
      }
    }
    return (hovered: null, popped: const {});
  }

  /// チップの帯をドラッグしている間、逐次呼ぶ（Start・Updateの両方から）。
  /// 指が乗っているチップへその場でタブを切り替え、飛び出させるチップの
  /// 集合を更新する。
  void _handleSwipeUpdate(Offset globalPosition, int tabCount, bool vertical) {
    // showAppDialog/showGeneralDialog/showMenu等のポップアップはNavigatorに
    // ルートとして積まれる。ここで弾かないと、開いたポップアップの背後で
    // タブが切り替わってしまい、以前の実装が「一貫して動作しない」原因に
    // なっていた（ポップアップの種類によってバリアの有無・挙動が異なり、
    // スワイプが素通りするものとしないものが混在していた為）。
    // 以前は`ModalRoute.isCurrent`で判定していたが、2026-10-04以降は戻る用の
    // 透明ルート`/_b/*`が常にホームの上に積まれてisCurrentが常にfalseになり、
    // なぞり遷移が一切効かなくなっていた（2026-10-10修正）。透明ルートを
    // 数えない`hasOpenOverlay`で判定する。
    if (ref.read(backStackControllerProvider).hasOpenOverlay) return;
    final order = _displayOrderNow();
    final hit = _hitTestChips(globalPosition, vertical, order);
    final selectionChanged =
        hit.hovered != null && hit.hovered != _selectedIndex;
    final poppedChanged = !setEquals(hit.popped, _poppedIndexes);
    if (!selectionChanged && !poppedChanged) return;
    setState(() {
      _poppedIndexes = hit.popped;
      if (selectionChanged)
        _setSelectedIndex(hit.hovered!.clamp(0, tabCount - 1));
    });
  }

  /// `_selectedIndex`（`IndexedStack`用のローカル状態）と
  /// `homeSelectedTabProvider`（外部から「今どのタブを見ているか」を
  /// 参照する為のミラー、`PinnedCallOverlay`が使う）を常に同期させて
  /// 更新する（2026-08-19追加）。呼び出し側で`setState`のcallback内から
  /// 呼ぶこと（`_selectedIndex`自体の代入がsetStateのcallback内で
  /// 行われるようにする為）。
  void _setSelectedIndex(int index) {
    _selectedIndex = index;
    _slideFrom = null;
    _slide.stop();
    _syncBackScope();
    ref.read(homeSelectedTabProvider.notifier).set(index);
  }

  /// 現在のタブに対応する戻る・進む履歴のスコープを[BackStackController]へ
  /// 伝える（2026-10-06追加）。
  void _syncBackScope() {
    ref.read(backStackControllerProvider).activeScope =
        BackScope.values[_selectedIndex.clamp(0, 2)];
  }

  static const _icons = [
    Icons.forum_outlined,
    Icons.face_outlined,
    Icons.settings_outlined,
    Icons.switch_account_outlined,
  ];

  /// [_icons]の各グリフの見た目の密度差を補正する表示サイズ
  /// （2026-08-27追加）。face_outlined/settings_outlinedはforum_outlinedより
  /// グリフ内側の余白が大きく同じ24でも小さく見える為、個別に拡大する。
  static const _iconSizes = [24.0, 28.0, 28.0, 26.0];

  static const _chipSize = kNavChipSize;
  static const _chipGap = kNavChipGap;
  static const _chipMargin = kNavChipMargin;

  @override
  Widget build(BuildContext context) {
    // 通話ミニ表示（PinnedCallOverlay）タップ等、このWidgetツリーの外側
    // から`homeSelectedTabProvider`が変更された場合にも、ローカルの
    // `_selectedIndex`（IndexedStackの描画に使う実体）へ反映する
    // （2026-08-19追加）。`_setSelectedIndex`は逆方向（ローカル→
    // プロバイダ）に既に反映済みの為、値が一致していれば何もしない
    // （ここでの再代入によるループは発生しない）。
    ref.listen<int>(homeSelectedTabProvider, (previous, next) {
      if (next != _selectedIndex) {
        final appear = ref
            .read(homeTabAppearRequestProvider.notifier)
            .consume();
        setState(() {
          _slideFrom = _selectedIndex;
          _selectedIndex = next;
          _appear = appear;
        });
        _slide.forward(from: 0);
        _syncBackScope();
      }
    });

    final strings = ref.watch(appStringsProvider);
    final titles = [
      strings.navTalk,
      strings.navProfile,
      strings.navSettings,
      strings.navAccount,
    ];

    // チップのタップ・なぞりの`setState`のたびに各タブが再構築されないよう、
    // `currentUser`が変わった時だけ作り直す（2026-10-10追加）。語らいタブは
    // 再構築のたびに購読を張り直すため、チップ操作で一覧が一瞬点滅していた。
    if (_cachedTabs == null || _cachedTabsUser != widget.currentUser) {
      _cachedTabsUser = widget.currentUser;
      _cachedTabs = [
        TalksTab(currentUser: widget.currentUser),
        ProfileTab(currentUser: widget.currentUser),
        SettingsTab(currentUser: widget.currentUser),
        AccountTab(currentUser: widget.currentUser),
      ];
    }
    final tabs = _cachedTabs!;

    final isWide = MediaQuery.sizeOf(context).width >= _kWideLayoutBreakpoint;

    // 並びは狭い画面（下部）・広い画面（サイドバー）とも設定に従う。揃えは狭い画面
    // だけ（2026-11-01）。各チップは論理インデックス`i`のまま、並ぶ順だけが変わる。
    final chipLayout = ref.watch(navChipLayoutProvider);
    final showAccount =
        ref.watch(accountTabVisibleProvider) &&
        chipLayout.accountChipEnabled &&
        !isWide;
    final displayOrder = visibleNavChipIndexes(
      chipLayout.order,
      showAccount: showAccount,
    );
    // 「アカウント」のチップが消えた時（保存が2つ未満に戻った・画面が横表示になった）、
    // そのタブを開いていたら語らいへ戻す（2026-11-11）。
    if (!showAccount && _selectedIndex == HomeTabId.account.index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedIndex == HomeTabId.account.index) {
          setState(() => _setSelectedIndex(kTalksTabIndex));
        }
      });
    }
    final chips = [
      for (final i in displayOrder)
        NavChip(
          key: _chipKeys[i],
          icon: _icons[i],
          iconSize: _iconSizes[i],
          label: titles[i],
          selected: _selectedIndex == i,
          popped: _isDragging && _poppedIndexes.contains(i),
          vertical: isWide,
          onTap: () => setState(() => _setSelectedIndex(i)),
        ),
    ];

    // タブ切り替えは、チップの帯（帯の上でのなぞり操作）のみで受け付ける。
    // タブのコンテンツ領域は各タブ固有のスワイプ操作（設定・身だしなみ・
    // 運営の狭い画面でのドリルダウン、語らいの一対/広場切り替え）に使うため、
    // ここではホームタブ切り替えのジェスチャーを付けない。指を離すまで
    // 連続的に切り替わるよう、ドラッグ中（Start・Update）の指の位置で逐次
    // 判定する（_handleSwipeUpdate参照、2026-07-29変更。以前はEndイベントの
    // 速度で隣へ1段階だけ移動する実装だった）。チップが横並び（モバイル）
    // なら横方向、縦並び（広い画面のサイドバー）なら縦方向のドラッグで反応する。
    // スマホのアイコン+寄合一覧では、条件を満たす時アイコン列が画面の下限まで伸びる
    // （語らいタブだけ下余白を外す。寄合一覧側の余白は語らいタブが自分で取る）。
    final extendTalksToBottom =
        !isWide &&
        iconRailExtendsToBottom(
          context,
          style: ref.watch(talksListLayoutStyleProvider),
          mirrored: ref.watch(iconSplitMirroredProvider),
          chipAlignment: chipLayout.alignment,
        );
    const bottomInset = _chipSize + _chipMargin * 2;
    final content = Padding(
      padding: isWide
          ? const EdgeInsets.only(left: _chipSize + _chipMargin * 2)
          : EdgeInsets.zero,
      // 戻る・進むはタブ毎の履歴で、タブをまたいで戻らない（2026-10-06変更、
      // 以前は語らい以外のタブで戻ると語らいタブへ戻る`BackEntry`だった）。
      // 現在のタブを`BackStackController.activeScope`へ伝える。
      // 非選択のタブもマウントされたままの為、見えているタブだけを
      // `PaneVisibility`で「表示中」と伝える（通話ミニ表示の出し分け用）。
      // 非選択のタブもマウントしたまま（`maintainState`）、スライド中だけ前後2枚を
      // チップの表示順に沿って横に並べて動かす。
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, _) {
          final from = _slideFrom;
          final t = Curves.easeOutCubic.transform(_slide.value);
          double posOf(int i) => displayOrder.indexOf(i).toDouble();
          final current =
              (from == null
                  ? posOf(_selectedIndex)
                  : posOf(from) + (posOf(_selectedIndex) - posOf(from)) * t) -
              _drag;
          // 「現れ方」の切り替え（`_appear`）は、横に動かさず、切り替え先を今の画面の上に
          // ダイアログと同じ動き（画面遷移の設定）で出す。木の形は常に同じ（各タブを
          // `buildDialogTransition`で包み、普段は止まった1.0を渡す）にして、タブの状態が
          // 作り直されないようにする。重なりは切り替え先が一番上になるよう並べ替える
          // （キー付きなので状態は保たれる）。
          final appearing = _appear && from != null;
          final order = [for (var i = 0; i < tabs.length; i++) i];
          if (appearing) {
            order.remove(_selectedIndex);
            order.add(_selectedIndex);
          }
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (final i in order)
                  Visibility(
                    key: ValueKey('home-tab-$i'),
                    // 並びに無いタブ（保存が2つ未満の「アカウント」）は、選ばれている時以外は出さない。
                    visible: appearing
                        ? (i == _selectedIndex || i == from)
                        : (i == _selectedIndex ||
                              i == from ||
                              (displayOrder.contains(i) &&
                                  (posOf(i) - current).abs() < 1)),
                    maintainState: true,
                    child: FractionalTranslation(
                      translation: appearing
                          ? Offset.zero
                          : Offset(posOf(i) - current, 0),
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom:
                              isWide ||
                                  (i == kTalksTabIndex && extendTalksToBottom)
                              ? 0
                              : bottomInset,
                        ),
                        child: buildDialogTransition(
                          appearing && i == _selectedIndex
                              ? _slide
                              : const AlwaysStoppedAnimation<double>(1),
                          PaneVisibility(
                            visible: i == _selectedIndex,
                            child: tabs[i],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );

    Widget wrapWithSwipe(Widget child, {required bool vertical}) {
      _stripVertical = vertical;
      void onStart(Offset globalPosition) {
        setState(() => _isDragging = true);
        _handleSwipeUpdate(globalPosition, tabs.length, vertical);
      }

      void onUpdate(Offset globalPosition) {
        _handleSwipeUpdate(globalPosition, tabs.length, vertical);
      }

      void onEnd() {
        if (_isDragging || _poppedIndexes.isNotEmpty) {
          setState(() {
            _isDragging = false;
            _poppedIndexes = {};
          });
        }
      }

      return Listener(
        key: _stripKey,
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _onStripPointerDown(e.position, vertical),
        onPointerMove: (e) => _onStripPointerMove(e.position),
        onPointerUp: (_) => _onStripPointerEnd(commit: true),
        onPointerCancel: (_) => _onStripPointerEnd(commit: false),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: vertical
              ? null
              : (details) => onStart(details.globalPosition),
          onHorizontalDragUpdate: vertical
              ? null
              : (details) => onUpdate(details.globalPosition),
          onHorizontalDragEnd: vertical ? null : (_) => onEnd(),
          onHorizontalDragCancel: vertical ? null : onEnd,
          onVerticalDragStart: !vertical
              ? null
              : (details) => onStart(details.globalPosition),
          onVerticalDragUpdate: !vertical
              ? null
              : (details) => onUpdate(details.globalPosition),
          onVerticalDragEnd: !vertical ? null : (_) => onEnd(),
          onVerticalDragCancel: !vertical ? null : onEnd,
          child: child,
        ),
      );
    }

    // ホーム表示中は常に履歴の「ベース」エントリを積み、戻るボタンでアプリの
    // 外（ホームより前）へ出ないようにする（2026-10-04追加）。
    return BackBaseGuard(
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              // 劇画スタイル時のハーフトーン柄・ダイアゴナルアクセントの背景装飾
              // （2026-07-30追加）は、語らいタブ等で中途半端に模様が透けて見える
              // 見た目が良くないとの指摘を受け廃止した（2026-08-04）。背景は
              // テーマの`scaffoldBackgroundColor`（`GekigaColors.background`）
              // による単色の塗り潰しのみにする。
              content,
              if (isWide)
                Positioned(
                  left: _chipMargin,
                  top: 0,
                  bottom: 0,
                  // GestureDetectorをCenterの外側に置くことで、当たり判定を
                  // チップ自体の大きさではなく帯全体（Positionedの領域）に
                  // 広げる。内側だとCenterの中でChild自身のサイズに縮んで
                  // しまい、チップとチップの間の余白でスワイプしても
                  // 反応しなかった。
                  child: wrapWithSwipe(
                    vertical: true,
                    Align(
                      alignment: switch (chipLayout.wideAlignment) {
                        NavChipAlignment.start => Alignment.topCenter,
                        NavChipAlignment.center => Alignment.center,
                        NavChipAlignment.end => Alignment.bottomCenter,
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: _chipMargin,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < chips.length; i++) ...[
                              if (i > 0) const SizedBox(height: _chipGap),
                              chips[i],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _chipMargin,
                  child: wrapWithSwipe(
                    vertical: false,
                    Align(
                      alignment: switch (chipLayout.alignment) {
                        NavChipAlignment.start => Alignment.centerLeft,
                        NavChipAlignment.center => Alignment.center,
                        NavChipAlignment.end => Alignment.centerRight,
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _chipMargin,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < chips.length; i++) ...[
                              if (i > 0) const SizedBox(width: _chipGap),
                              chips[i],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// チップ列を[ItemPickBridge]の登録先にする（2026-11-05）。語らいの部品（一対・広場の
/// 切り替えなど）を押したまま指をチップへ滑らせると、その場でタブが切り替わる。
/// 項目一覧と違い「選ぶ＝タブを切り替える」ので、確定（指を離す）では何も足さない。
class _ChipStripPickTarget implements ItemPickTarget {
  _ChipStripPickTarget(this._state);

  final _HomeScreenState _state;

  Rect? _stripRect() {
    final box = _state._stripKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  bool isActiveAt(Offset globalPosition) {
    if (!_state.mounted) return false;
    if (_state.ref.read(backStackControllerProvider).hasOpenOverlay) {
      return false;
    }
    return _stripRect()?.contains(globalPosition) ?? false;
  }

  @override
  int? indexAt(Offset globalPosition) {
    if (!isActiveAt(globalPosition)) return null;
    final order = _state._displayOrderNow();
    return _state
        ._hitTestChips(globalPosition, _state._stripVertical, order)
        .hovered;
  }

  @override
  void pick(int? index, {required bool commit}) =>
      _state._pickChip(index, commit: commit);
}
