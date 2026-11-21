import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/sticker.dart';
import '../../widgets/sticker_image.dart';
import '../../widgets/transitioned_overlay.dart';
import 'sticker_carousel.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../models/sticker_send_mode.dart';
import '../../providers/last_sticker_tab_provider.dart';
import '../../providers/owned_sticker_packs_provider.dart';
import '../../providers/recent_stickers_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/sticker_send_mode_provider.dart';

/// ぺったんピッカーの本体（検索バー＋パック別レール＋グリッド、2026-08-11
/// 追加）。モバイル用ボトムシート（`StickerPickerSheet`）とデスクトップ用
/// アンカーポップアップ（`sticker_picker_popup.dart`）の両方から共有される。
/// [railAxis]で、パック切り替えレールを左サイド（`Axis.vertical`）に
/// 出すか下部（`Axis.horizontal`）に出すかを切り替える。
/// 「最近使った」タブを表す[StickerPickerContent]内部のタブid。
const _kRecentTab = kStickerTabRecent;

class StickerPickerContent extends ConsumerStatefulWidget {
  const StickerPickerContent({
    required this.railAxis,
    required this.onStickerSelected,
    this.initialPackId,
    this.conversationKey,
    this.scrollLocked = false,
    this.onGridVerticalDragUpdate,
    this.onGridVerticalDragEnd,
    this.onGridOverscrollTop,
    this.dismissing,
    super.key,
  });

  final Axis railAxis;

  /// 語らい（寄合）毎に、直前に開いたタブを記憶・復元するキー
  /// （`stickerTabKey`）。nullなら記憶しない（2026-10-30）。
  final String? conversationKey;

  /// trueの間は、グリッドの縦スクロールを止める（モバイルのドックが半分の状態）。
  /// 代わりにグリッド領域の縦ドラッグを[onGridVerticalDragUpdate]・
  /// [onGridVerticalDragEnd]（ドックの高さの変更）へ回す（2026-10-30）。
  final bool scrollLocked;
  final void Function(double dy)? onGridVerticalDragUpdate;
  final void Function(double velocity)? onGridVerticalDragEnd;

  /// グリッドが先頭にいる状態でさらに下へ引かれ、一定量たまった時（ドックが
  /// 拡大から半分へ縮む合図）。
  final VoidCallback? onGridOverscrollTop;

  /// trueになったら、ポップアップが閉じ始めた合図（2026-11-21）。拡大プレビューは別の
  /// オーバーレイなので、閉じる動きの間も残らないよう、すぐ消す。
  final ValueListenable<bool>? dismissing;

  /// モバイル（レールが下）かどうか。横スワイプでタブを移動出来る。
  bool get _swipeTabs => railAxis == Axis.horizontal;
  final void Function(Sticker sticker) onStickerSelected;

  /// 指定時は「全て」タブではなく、このパックに絞り込んだ状態で開く
  /// （他人が送信済みのぺったんをタップして開く導線用、2026-08-14追加）。
  final String? initialPackId;

  @override
  ConsumerState<StickerPickerContent> createState() =>
      _StickerPickerContentState();
}

class _StickerPickerContentState extends ConsumerState<StickerPickerContent> {
  String _query = '';
  // nullは「全て」タブを表す。[_kRecentTab]は「最近使った」タブ。
  String? _chosenPackId;
  // 利用者がタブを選んだか。選ぶまでは[_selectedPackId]が既定（指定パック、
  // 無ければ最近があれば「最近」、無ければ「全て」）を返す。最近の読み込みは
  // 非同期の為、初期化時ではなく都度判定する（2026-10-29）。
  bool _tabChosen = false;

  // 所持パックのid（取得出来た後）。記憶したパックが今も有効かの判定に使う。
  Set<String>? _ownedPackIds;

  /// 開いた時の最初のタブ: 指定パック → この語らいで直前に開いたタブ（パックは
  /// 今も所持している時だけ）→ 最近があれば最近 → 全て。
  String? get _selectedPackId {
    if (_tabChosen) return _chosenPackId;
    if (widget.initialPackId != null) return widget.initialPackId;
    final key = widget.conversationKey;
    final remembered = key == null
        ? null
        : ref.read(lastStickerTabProvider)[key];
    if (remembered == kStickerTabAll) return null;
    if (remembered == kStickerTabRecent) return _kRecentTab;
    if (remembered != null && (_ownedPackIds?.contains(remembered) ?? false)) {
      return remembered;
    }
    return ref.read(recentStickersProvider).isNotEmpty ? _kRecentTab : null;
  }

  void _selectTab(String? packId) {
    // 別のぺったんのパック（タブ）を開いたら、拡大表示は閉じる（2026-11-21）。
    _removePreview();
    setState(() {
      _tabChosen = true;
      _chosenPackId = packId;
    });
    // 利用者が選んだタブだけを、この語らいの「直前に開いたタブ」として記憶する。
    final key = widget.conversationKey;
    if (key != null) {
      ref
          .read(lastStickerTabProvider.notifier)
          .remember(key, packId ?? kStickerTabAll);
    }
  }

  // 横スワイプでタブを移動する（モバイル）ためのページ制御。コントローラーは
  // 初期ページが決まってから作る（所持パックの取得後）。
  PageController? _pageController;
  final _railController = ScrollController();
  bool _pageAnimating = false;
  // 拡大中の下引きで縮小する判定用（[_buildPager]参照）。
  Offset? _collapseStart;
  bool _gridAtTop = true;

  /// タブの並び（レールと同じ: 最近、全て(null)、所持パック）。
  List<String?> _tabIds(List<StickerPack> packs) => [
    _kRecentTab,
    null,
    for (final pack in packs)
      if (pack.stickers.isNotEmpty) pack.packId,
  ];

  int _tabIndex(List<String?> tabs) {
    final i = tabs.indexOf(_selectedPackId);
    return i < 0 ? 1 : i;
  }

  /// 選択中のタブが横レールの見える範囲に入るようスクロールする。
  void _scrollRailTo(int index) {
    if (!_railController.hasClients) return;
    final position = _railController.position;
    final target = (index * 48.0 + 8 + 24 - position.viewportDimension / 2)
        .clamp(0.0, position.maxScrollExtent);
    _railController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _goToTab(List<String?> tabs, int index) async {
    _selectTab(tabs[index]);
    _scrollRailTo(index);
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    _pageAnimating = true;
    await controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    _pageAnimating = false;
  }

  void _onPageChanged(List<String?> tabs, int index) {
    if (_pageAnimating || index >= tabs.length) return;
    if (tabs[index] == _selectedPackId) return;
    _selectTab(tabs[index]);
    _scrollRailTo(index);
  }

  // LINE型送信方式の拡大プレビュー用（2026-08-13追加）。
  Sticker? _pendingPreviewSticker;
  Offset? _pendingTapGlobalPos;
  Offset? _lastTapDownGlobalPos;
  TransitionedOverlayHandle? _previewEntry;

  // 拡大プレビューの中で、スクロール（ホイール・横スワイプ）で隣のぺったんへ切り替える
  // ための、プレビュー元の一覧（表示順、2026-11-21）。切り替えの動きは提案パネルの拡大と
  // 同じ[StickerCarousel]で行う。
  List<Sticker> _previewSource = const [];

  /// 直近の押下が、一覧のぺったん自体の上だったか。ポップアップの他の場所を押した時に
  /// 拡大表示を閉じる為の判定（2026-11-21）。
  bool _pointerOnSticker = false;

  void _onDismissing() {
    if (widget.dismissing?.value ?? false) _removePreview();
  }

  @override
  void initState() {
    super.initState();
    widget.dismissing?.addListener(_onDismissing);
  }

  @override
  void dispose() {
    widget.dismissing?.removeListener(_onDismissing);
    // ピッカー自体が閉じられた（ボトムシートのスワイプ・ポップアップ外
    // タップ等）際に、挿入済みのOverlayEntryがルートOverlayに残り続ける
    // リークを防ぐ。残ると、拡大表示だけが残る上、閉じた後の`State`の`context`を
    // 触ってエラーになる。
    _previewEntry?.removeNow();
    _previewEntry = null;
    _pageController?.dispose();
    _railController.dispose();
    super.dispose();
  }

  void _handleStickerTap(
    Sticker sticker,
    StickerSendMode mode, [
    List<Sticker>? source,
  ]) {
    if (mode == StickerSendMode.discord) {
      widget.onStickerSelected(sticker);
      return;
    }
    // LINE型: 直前にプレビュー中だったのと同じぺったんの2回目タップなら送信。
    if (_pendingPreviewSticker?.stickerId == sticker.stickerId) {
      _removePreview();
      widget.onStickerSelected(sticker);
      return;
    }
    // 1回目のタップ、又は別のぺったんへの差し替え。
    if (source != null) _previewSource = source;
    _pendingPreviewSticker = sticker;
    _pendingTapGlobalPos = _lastTapDownGlobalPos;
    if (_previewEntry == null) {
      // 拡大表示も、アプリの画面遷移の設定に従って出し入れする（2026-11-21）。
      late final TransitionedOverlayHandle handle;
      Widget? last;
      handle = showTransitionedOverlayHandle(
        Overlay.of(context),
        builder: (_, _) {
          // 閉じる動きの間は、直前の見た目を保つ（状態は既に片付いている）。閉じ始めた後の
          // 再描画では、閉じた後の`State`を触らない。
          if (identical(_previewEntry, handle) &&
              _pendingPreviewSticker != null) {
            last = Stack(children: [_buildPreviewOverlay()]);
          }
          return last ?? const SizedBox.shrink();
        },
      );
      _previewEntry = handle;
    } else {
      _previewEntry!.markNeedsBuild();
    }
  }

  void _removePreview() {
    // 閉じる動きを再生してから取り除く。
    _previewEntry?.close();
    _previewEntry = null;
    _pendingPreviewSticker = null;
    _pendingTapGlobalPos = null;
  }

  Widget _buildPreviewOverlay() {
    final sticker = _pendingPreviewSticker;
    final anchor = _pendingTapGlobalPos;
    if (sticker == null || anchor == null) return const SizedBox.shrink();

    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final screenSize = overlayBox.size;
    const screenPad = 8.0;
    // ピッカー本体（ポップアップ・ボトムシート）の矩形。プレビューはこの真上に
    // 出し、選んでいるぺったん一覧を隠さない（2026-10-29）。上に十分な余白が
    // 無い時だけ、従来どおりタップ位置の近くに重ねる。
    final pickerBox = context.findRenderObject() as RenderBox?;
    final pickerRect = (pickerBox != null && pickerBox.hasSize)
        ? pickerBox.localToGlobal(Offset.zero) & pickerBox.size
        : null;
    final roomAbove = pickerRect == null
        ? 0.0
        : pickerRect.top - screenPad * 2 - 8;
    final above = roomAbove >= 160;
    final previewSize = above ? math.min(320.0, roomAbove) : 240.0;
    // 左右に隣のぺったんが覗くよう、プレビューは横に広いカードにする。
    final cardWidth = math.min(
      previewSize * 1.9,
      screenSize.width - screenPad * 2,
    );
    final maxLeft = math.max(
      screenPad,
      screenSize.width - cardWidth - screenPad,
    );
    final maxTop = math.max(
      screenPad,
      screenSize.height - previewSize - screenPad,
    );
    final left = ((above ? pickerRect!.center.dx : anchor.dx) - cardWidth / 2)
        .clamp(screenPad, maxLeft);
    final top =
        (above
                ? pickerRect!.top - previewSize - 8
                : anchor.dy - previewSize - 24)
            .clamp(screenPad, maxTop);

    final source = _previewSource.isEmpty ? [sticker] : _previewSource;
    final currentIndex = source
        .indexWhere((s) => s.stickerId == sticker.stickerId)
        .clamp(0, source.length - 1);
    return Positioned(
      left: left,
      top: top,
      width: cardWidth,
      height: previewSize,
      child: Material(
        // 劇画UIでは、黒ではなく劇画の背景色（アクセント）にする（2026-10-29）。
        color: ref.watch(appUiStyleProvider) == AppUiStyle.gekiga
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        elevation: 8,
        shadowColor: Theme.of(context).colorScheme.shadow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        // 提案パネルの拡大と同じカルーセル（2026-11-21）。中央が大きく、左右に隣が覗き、
        // 横スワイプ・ホイールで切り替わる。中央のタップ＝「同じぺったんをもう一度タップ」
        // と同義で送信する。
        child: StickerCarousel(
          stickers: source,
          index: currentIndex,
          onIndexChanged: (i) {
            _pendingPreviewSticker = source[i];
            _previewEntry?.markNeedsBuild();
          },
          onSend: (sticker) {
            _removePreview();
            widget.onStickerSelected(sticker);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final currentUserId = ref.watch(authStateProvider).value?.uid;
    final sendMode = ref.watch(stickerSendModeProvider);
    // 最近の読み込み完了で、既定のタブを見直すため購読する。
    ref.watch(recentStickersProvider);
    ref.watch(lastStickerTabProvider);

    return Listener(
      // ポップアップのぺったん以外（検索欄・レール・余白）を押したら、拡大表示を閉じる。
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (!_pointerOnSticker) _removePreview();
        _pointerOnSticker = false;
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _withDockDragAlways(
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: strings.stickerSearchHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ),
          Expanded(
            child: currentUserId == null
                ? const SizedBox.shrink()
                : Builder(
                    builder: (context) {
                      // 所持パックは共有の1本の購読から読む（再ビルドで取り直さない）。
                      final packs =
                          ref
                              .watch(ownedStickerPacksProvider(currentUserId))
                              .value ??
                          const <StickerPack>[];
                      _ownedPackIds = {for (final pack in packs) pack.packId};
                      if (packs.isEmpty) {
                        return _buildGrid(strings, packs, sendMode, null);
                      }
                      final Widget content;
                      if (widget._swipeTabs) {
                        content = _buildPager(strings, packs, sendMode);
                      } else {
                        content = _buildGrid(
                          strings,
                          packs,
                          sendMode,
                          _selectedPackId,
                        );
                      }
                      final rail = _buildRail(packs);
                      return widget.railAxis == Axis.vertical
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                rail,
                                const VerticalDivider(width: 1),
                                Expanded(child: content),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: content),
                                const Divider(height: 1),
                                rail,
                              ],
                            );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRail(List<StickerPack> packs) {
    final items = <({String? packId, String imageUrl})>[
      (packId: null, imageUrl: packs.first.stickers.first.imageUrl),
      for (final pack in packs)
        if (pack.stickers.isNotEmpty)
          (packId: pack.packId, imageUrl: pack.stickers.first.imageUrl),
    ];
    final tabs = _tabIds(packs);
    final railChildren = [
      _RailIcon(
        imageUrl: '',
        selected: _selectedPackId == _kRecentTab,
        isAllTab: false,
        icon: Icons.history,
        tooltip: ref.read(appStringsProvider).stickerRecentTab,
        onTap: () => _goToTab(tabs, 0),
      ),
      for (final item in items)
        _RailIcon(
          imageUrl: item.imageUrl,
          selected: _selectedPackId == item.packId,
          isAllTab: item.packId == null,
          onTap: () => widget._swipeTabs
              ? _goToTab(tabs, tabs.indexOf(item.packId))
              : _selectTab(item.packId),
        ),
    ];
    if (widget.railAxis == Axis.vertical) {
      return SizedBox(
        width: 56,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: railChildren,
        ),
      );
    }
    return _withDockDragAlways(
      SizedBox(
        height: 56,
        child: ListView(
          controller: _railController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: railChildren,
        ),
      ),
    );
  }

  /// 横スワイプでタブを移動するグリッド群（モバイル）。
  Widget _buildPager(
    Strings strings,
    List<StickerPack> packs,
    StickerSendMode mode,
  ) {
    final tabs = _tabIds(packs);
    final index = _tabIndex(tabs);
    final controller = _pageController ??= PageController(initialPage: index);
    // 利用者がまだ選んでいない間に既定のタブが変わった（最近の読み込み完了等）
    // 場合だけ、ページを合わせる。選んだ後は、スワイプ・レールで常に一致している。
    if (!_tabChosen && controller.hasClients) {
      final page = controller.page?.round();
      if (page != null && page != index) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && controller.hasClients) controller.jumpToPage(index);
        });
      }
    }
    // 拡大中の「先頭から下へ引くと半分へ縮む」は、ジェスチャーの競り合い
    // （横のPageView／縦のGridView）やオーバースクロール通知に頼らず、ポインターの
    // 動きを直接見て判定する（実機でオーバースクロールが発火しなかった為）。
    return Listener(
      onPointerDown: (event) =>
          _collapseStart = _gridAtTop ? event.position : null,
      onPointerMove: (event) {
        final start = _collapseStart;
        if (start == null || widget.scrollLocked) return;
        final delta = event.position - start;
        // 縦優先（斜めでも）で下へ約40px動いたら縮小を通知する。
        if (delta.dy > 40 && delta.dy > delta.dx.abs() * 1.5) {
          _collapseStart = null;
          widget.onGridOverscrollTop?.call();
        }
      },
      onPointerUp: (_) => _collapseStart = null,
      onPointerCancel: (_) => _collapseStart = null,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            _gridAtTop =
                notification.metrics.pixels <=
                notification.metrics.minScrollExtent + 0.5;
          }
          return false;
        },
        child: PageView.builder(
          controller: controller,
          itemCount: tabs.length,
          onPageChanged: (i) => _onPageChanged(tabs, i),
          itemBuilder: (context, i) =>
              _buildGrid(strings, packs, mode, tabs[i]),
        ),
      ),
    );
  }

  /// 検索欄・下のレールの領域でも、縦ドラッグをドックの高さの変更（展開・縮小・
  /// 閉じる）として受ける。バーと同じ操作の判定範囲を広げる為で、一覧と違い
  /// 段に関わらず常に有効（拡大中も、ここを下に引けば半分・閉じるへ進める）。
  /// 横の動き（レールのスクロール・検索欄の文字選択）はそのまま。ドックから
  /// 渡されない（PCポップアップ）時は何もしない。
  Widget _withDockDragAlways(Widget child) {
    if (widget.onGridVerticalDragUpdate == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (details) =>
          widget.onGridVerticalDragUpdate?.call(details.delta.dy),
      onVerticalDragEnd: (details) =>
          widget.onGridVerticalDragEnd?.call(details.primaryVelocity ?? 0),
      child: child,
    );
  }

  /// スクロールを止めている間（ドックが半分）、縦ドラッグをドックの高さの変更へ
  /// 回すためにグリッド領域を包む。そうでなければそのまま返す。
  Widget _withDockDrag(Widget child) {
    if (!widget.scrollLocked || widget.onGridVerticalDragUpdate == null) {
      return child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (details) =>
          widget.onGridVerticalDragUpdate?.call(details.delta.dy),
      onVerticalDragEnd: (details) =>
          widget.onGridVerticalDragEnd?.call(details.primaryVelocity ?? 0),
      child: child,
    );
  }

  Widget _buildGrid(
    Strings strings,
    List<StickerPack> packs,
    StickerSendMode mode,
    String? selectedPackId,
  ) {
    final query = _query.trim().toLowerCase();
    final List<Sticker> source;
    if (selectedPackId == _kRecentTab) {
      // 所持パック内のぺったんを、最近使った順に並べる（所持していない・削除
      // 済みのものは出さない）。
      final byId = {
        for (final pack in packs)
          for (final sticker in pack.stickers) sticker.stickerId: sticker,
      };
      source = [
        for (final id in ref.watch(recentStickersProvider))
          if (byId[id] != null) byId[id]!,
      ];
    } else {
      source = packs
          .where(
            (pack) => selectedPackId == null || pack.packId == selectedPackId,
          )
          .expand((pack) => pack.stickers)
          .toList();
    }
    final stickers = source
        .where(
          (sticker) =>
              query.isEmpty || sticker.name.toLowerCase().contains(query),
        )
        .toList();
    if (stickers.isEmpty) {
      return _withDockDrag(
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              strings.chatNoStickersMessage,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final grid = GridView.builder(
      // ドックから縦ドラッグの処理を渡された時（モバイル）だけ、半分の間は
      // スクロールを止め、端でのクランプにそろえる。
      physics: widget.onGridVerticalDragUpdate == null
          ? null
          : widget.scrollLocked
          ? const NeverScrollableScrollPhysics()
          : const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, index) {
        final sticker = stickers[index];
        return Listener(
          // ぺったん自体の操作は、拡大表示の切り替え・送信に使うので、ポップアップをクリック
          // した時に拡大表示を閉じる処理の対象外にする（印を付ける。深い方が先に呼ばれる）。
          onPointerDown: (_) => _pointerOnSticker = true,
          child: InkWell(
            onTapDown: (details) =>
                _lastTapDownGlobalPos = details.globalPosition,
            onTap: () => _handleStickerTap(sticker, mode, stickers),
            child: StickerImage(
              sticker.imageUrl,
              // 原寸のままデコードすると、多数並ぶ一覧で重いため縮小して読む。
              cacheWidth: 256,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    );
    return _withDockDrag(grid);
  }
}

class _RailIcon extends StatelessWidget {
  const _RailIcon({
    required this.imageUrl,
    required this.selected,
    required this.isAllTab,
    required this.onTap,
    this.icon,
    this.tooltip,
  });

  /// 指定時は画像の代わりにこのアイコンを出す（「最近使った」タブ）。
  final IconData? icon;
  final String? tooltip;

  final String imageUrl;
  final bool selected;
  final bool isAllTab;
  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = Padding(
      padding: const EdgeInsets.all(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.all(4),
          child: ClipOval(
            child: (isAllTab || icon != null)
                ? Icon(
                    icon ?? Icons.apps,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  )
                : StickerImage(
                    imageUrl,
                    cacheWidth: 96,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined, size: 20),
                  ),
          ),
        ),
      ),
    );
    return tooltip == null ? item : Tooltip(message: tooltip!, child: item);
  }
}
