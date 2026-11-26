import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pressable_scale.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../theme/block/block_theme.dart';
import '../theme/gekiga/gekiga_colors.dart';
import 'gekiga/gekiga_badge.dart';
import 'glass/glass_surface.dart';
import '../providers/selection_motion_provider.dart';
import '../theme/chalk/chalk_paint.dart';
import 'chalk_nav_bar.dart';
import 'washi_nav_bar.dart';
import 'liquid_chip_highlight.dart';

/// ナビチップの直径と、チップ同士・画面端との間隔（ホーム画面
/// `lib/features/home/home_screen.dart`と管理画面で共通）。
const kNavChipSize = 56.0;
const kNavChipGap = 16.0;
const kNavChipMargin = 16.0;

/// サイドバー（縦並び）と下部（横並び）を切り替える画面幅のしきい値。
/// Material Design 3のmedium windowサイズクラス（600dp）を採用する。
const kNavChipWideBreakpoint = 600.0;

/// メニューバーを使わず、タブ切り替えを1つずつ独立した丸いチップで表す。
/// 選択中はアクセントカラーで塗り、常に浮いて見えるよう影を付ける。
/// 劇画スタイル時は丸いチップの代わりにジグザグのバッジ意匠を使う
/// （2026-07-30、appUiStyleProviderを見るためConsumerWidget化）。
/// ホーム画面の`_NavChip`を、管理画面でも同じ見た目にするため公開した
/// （2026-10-10、見た目・挙動は変えていない）。
class NavChip extends ConsumerWidget {
  const NavChip({
    required this.icon,
    required this.iconSize,
    required this.label,
    required this.selected,
    required this.popped,
    required this.vertical,
    required this.onTap,
    this.liquid = false,
    super.key,
  });

  final IconData icon;
  final double iconSize;
  final String label;
  final bool selected;

  /// なぞっている間、選択中のこのチップを帯からはみ出させて強調するか。
  final bool popped;

  /// チップが縦並び（広い画面のサイドバー）か。飛び出す方向の判定に使う
  /// （横並びなら上、縦並びなら右に飛び出す）。
  final bool vertical;

  final VoidCallback onTap;

  /// 選択色を、このチップでは塗らない（2026-11-26）。帯の上に重ねた`LiquidChipHighlight`が、
  /// 水が流れ込むように、選択中のチップへ塗りを移す。
  final bool liquid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 塗りを層に任せる時（`liquid`）は、選択の見た目（色・文字色）をここでは出さない。
    // 影の高さだけは、選択に従う。
    final elevated = selected;
    final sel = selected && !(liquid && ref.watch(navWaterMotionProvider));
    final colorScheme = Theme.of(context).colorScheme;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final isBlock = uiStyle == AppUiStyle.block;
    // チョーク・和紙: チップ自体は塗らない。印・枠は、帯（[ChalkNavBar]・[WashiNavBar]）が描く。
    final isChalk = uiStyle == AppUiStyle.chalk;
    final isWashi = uiStyle == AppUiStyle.washi;
    // 「丸で囲む」の時は、帯が1本になり、チップは塗らない（印・輪は帯が描く）。
    final merged = ref.watch(navBandMergedProvider);
    final brightness = Theme.of(context).brightness;
    final glassWater = liquid && isGlass && ref.watch(navWaterMotionProvider)
        ? LiquidChipScope.of(context, key)
        : null;
    // ガラスの選択色は、背景にアクセント色を45%で重ねた、不透明な色にする。半透明のままだと、
    // 下のぼかしや重ね方で色が変わり、水で塗った時と「なし」の時で、色が違って見えた。
    final glassSelectedFill = glassSelectedChipFill(context);
    final background = sel ? colorScheme.primary : colorScheme.surface;
    final foreground = sel
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    // popped中は帯から浮き出させ、指を離す（popped=falseに戻る）と
    // AnimatedSlideが規定位置までスライドして戻す。
    final offset = merged
        ? Offset.zero
        : popped && !(liquid && ref.watch(navWaterMotionProvider))
        ? (vertical ? const Offset(0.35, 0) : const Offset(0, -0.35))
        : Offset.zero;

    // 劇画スタイルは他のメニューチップ（GekigaMenuTile/GekigaPanelBox）と
    // 同じ「選択中=白地黒字、非選択中=黒地白字」の規則に統一する
    // （2026-08-04変更。以前は選択中のみアクセントカラー塗りのバッジだったが、
    // アクセントカラーは劇画UI選択中は変更不可にした為、この画面だけ
    // 固定色になったアクセントカラーが残るのは一貫しない）。
    final mergedIconColor = switch (uiStyle) {
      AppUiStyle.flat =>
        sel ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
      AppUiStyle.glass => colorScheme.onSurfaceVariant,
      AppUiStyle.block => sel ? colorScheme.onPrimary : colorScheme.onSurface,
      AppUiStyle.gekiga => sel ? GekigaColors.panel : GekigaColors.onPanel,
      AppUiStyle.chalk => colorScheme.onSurface,
      AppUiStyle.washi => sel ? colorScheme.onPrimary : colorScheme.onSurface,
    };
    final chip = merged
        ? Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: Stack(
              children: [
                // ガラスは、水を、チップの中で描く。
                if (glassWater != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: LiquidGlassFillPainter(
                          glassWater.$1,
                          glassWater.$2,
                          glassSelectedFill,
                        ),
                      ),
                    ),
                  ),
                InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: kNavChipSize,
                    height: kNavChipSize,
                    child: Icon(icon, size: iconSize, color: mergedIconColor),
                  ),
                ),
              ],
            ),
          )
        : isChalk
        // チョーク（分ける時）: チョークで引いた丸の縁。選択中の塗りはアクセントカラー。
        ? Material(
            color: sel ? colorScheme.primary : Colors.transparent,
            shape: ChalkShapeBorder(
              borderRadius: BorderRadius.circular(kNavChipSize / 2),
              color: colorScheme.onSurface,
              width: 2,
            ),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: kNavChipSize,
                height: kNavChipSize,
                child: Icon(
                  icon,
                  size: iconSize,
                  color: sel ? colorScheme.onPrimary : colorScheme.onSurface,
                ),
              ),
            ),
          )
        : isWashi
        // 和紙（分ける時）: へこんだ丸。選択中（なし）は、ざらつきのある印を重ねる。
        ? CustomPaint(
            painter: WashiInsetChipPainter(
              base: colorScheme.surface,
              fill: sel ? colorScheme.primary : null,
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: kNavChipSize,
                  height: kNavChipSize,
                  child: Icon(
                    icon,
                    size: iconSize,
                    color: sel ? colorScheme.onPrimary : colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          )
        : isGekiga
        ? Material(
            color: Colors.transparent,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: kNavChipSize,
                height: kNavChipSize,
                child: GekigaBadgeShape(
                  color: sel ? GekigaColors.onPanel : GekigaColors.panel,
                  seed: icon.hashCode,
                  invert: sel,
                  child: Icon(
                    icon,
                    size: iconSize,
                    color: sel ? GekigaColors.panel : GekigaColors.onPanel,
                  ),
                ),
              ),
            ),
          )
        : isGlass
        ? GlassSurface(
            // 選択中は、ぼかさない面にする。ぼかすと、隣の選択色の項目の色が回り込み、塗りの
            // 色が場所で変わって、一覧の選択色と違って見える（2026-11-26）。
            variant: selected ? GlassVariant.card : GlassVariant.chrome,
            borderRadius: BorderRadius.circular(kNavChipSize / 2),
            child: Material(
              color: sel ? glassSelectedFill : Colors.transparent,
              shape: const CircleBorder(),
              child: Stack(
                children: [
                  // 水で移す時は、塗りをここで描く（選択色の塗りと同じ重ね方になる）。
                  if (glassWater != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: LiquidGlassFillPainter(
                            glassWater.$1,
                            glassWater.$2,
                            glassSelectedFill,
                          ),
                        ),
                      ),
                    ),
                  InkWell(
                    onTap: onTap,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: kNavChipSize,
                      height: kNavChipSize,
                      // 選択・非選択で文字色は変えない（背景の塗りだけで選択状態を
                      // 表す、2026-08-29変更）。
                      child: Icon(
                        icon,
                        size: iconSize,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : isBlock
        // ブロック: 太い枠線とぼかしの無い硬い影（このスタイルだけの例外）。
        ? DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: BlockTheme.shadow(colorScheme.primary, brightness),
            ),
            child: Material(
              // ライトは灰色を重ねず、選択中=アクセント・非選択=白にする。
              color: sel
                  ? colorScheme.primary
                  : (brightness == Brightness.light
                        ? Colors.white
                        : colorScheme.surface),
              surfaceTintColor: Colors.transparent,
              shape: CircleBorder(
                side: BorderSide(
                  color: BlockTheme.lineColor(brightness),
                  width: BlockTheme.borderWidth,
                ),
              ),
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: kNavChipSize,
                  height: kNavChipSize,
                  child: Icon(icon, size: iconSize, color: foreground),
                ),
              ),
            ),
          )
        : Material(
            color: background,
            shape: const CircleBorder(),
            elevation: elevated ? 8 : 4,
            shadowColor: colorScheme.primary.withValues(alpha: 0.4),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: kNavChipSize,
                height: kNavChipSize,
                child: Icon(icon, size: iconSize, color: foreground),
              ),
            ),
          );

    // RepaintBoundaryで囲み、なぞっている間の飛び出しアニメーションが
    // 選択中タブの中身（語らい一覧など）まで巻き込んで再描画させないように
    // する（2026-07-29追加。囲む前はチップの帯全体・場合によっては背後の
    // コンテンツまで毎フレーム再描画され、実機でカクついて見えていた）。
    return RepaintBoundary(
      child: AnimatedSlide(
        offset: offset,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        // 押した時に少し沈み、離すと弾んで戻る（2026-11-05）。
        child: PressableScale(child: chip),
      ),
    );
  }
}

/// [NavChip]を並べたナビ（広い画面は左端に縦並び、狭い画面は下端に横並び）と
/// 内容領域を重ねる共通シェル。チップの帯の上でのなぞり操作で、指が乗った
/// チップへ連続的にタブを切り替える（ホーム画面と同じ操作感）。
///
/// ホーム画面（`HomeScreen`）は戻る・進む履歴のスコープ同期と密結合のため
/// 独自の実装のまま残しており、この部品は管理画面用（2026-10-10追加）。
class ChipNavShell extends StatefulWidget {
  const ChipNavShell({
    required this.icons,
    required this.iconSizes,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
    this.isSwipeBlocked,
    this.chipWrapper,
    super.key,
  });

  final List<IconData> icons;
  final List<double> iconSizes;
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 内容領域（`IndexedStack`等）。チップに隠れないよう余白は本部品が付ける。
  final Widget child;

  /// trueを返す間はなぞりによるタブ切り替えを無効にする（ポップアップが
  /// 開いている間に背後でタブが切り替わらないようにする為）。
  final bool Function()? isSwipeBlocked;

  /// 各チップを包む（ガイドの目印を巻く等、2026-10-17追加）。`null`なら包まない。
  final Widget Function(int index, Widget chip)? chipWrapper;

  @override
  State<ChipNavShell> createState() => _ChipNavShellState();
}

class _ChipNavShellState extends State<ChipNavShell> {
  bool _isDragging = false;
  Set<int> _poppedIndexes = {};
  late final List<GlobalKey> _chipKeys = List.generate(
    widget.icons.length,
    (_) => GlobalKey(),
  );

  List<Rect?> _chipGlobalRects() => [
    for (final key in _chipKeys)
      switch (key.currentContext?.findRenderObject()) {
        final RenderBox box => box.localToGlobal(Offset.zero) & box.size,
        _ => null,
      },
  ];

  /// [globalPosition]の下にあるチップ（`hovered`。隙間の上ならnull）と、
  /// 飛び出させるチップのindex集合（チップ真上なら1件、隙間の上なら前後2件）。
  ({int? hovered, Set<int> popped}) _hitTestChips(
    Offset globalPosition,
    bool vertical,
  ) {
    final rects = _chipGlobalRects();
    for (var i = 0; i < rects.length; i++) {
      final rect = rects[i];
      if (rect != null && rect.contains(globalPosition)) {
        return (hovered: i, popped: {i});
      }
    }
    for (var i = 0; i < rects.length - 1; i++) {
      final a = rects[i];
      final b = rects[i + 1];
      if (a == null || b == null) continue;
      final pastA = vertical
          ? globalPosition.dy >= a.bottom
          : globalPosition.dx >= a.right;
      final beforeB = vertical
          ? globalPosition.dy <= b.top
          : globalPosition.dx <= b.left;
      if (pastA && beforeB) {
        return (hovered: null, popped: {i, i + 1});
      }
    }
    return (hovered: null, popped: const {});
  }

  void _handleSwipeUpdate(Offset globalPosition, bool vertical) {
    if (widget.isSwipeBlocked?.call() ?? false) return;
    final hit = _hitTestChips(globalPosition, vertical);
    final selectionChanged =
        hit.hovered != null && hit.hovered != widget.selectedIndex;
    final poppedChanged = !setEquals(hit.popped, _poppedIndexes);
    if (!selectionChanged && !poppedChanged) return;
    setState(() => _poppedIndexes = hit.popped);
    if (selectionChanged) {
      widget.onSelected(hit.hovered!.clamp(0, widget.icons.length - 1));
    }
  }

  void _endDrag() {
    if (_isDragging || _poppedIndexes.isNotEmpty) {
      setState(() {
        _isDragging = false;
        _poppedIndexes = {};
      });
    }
  }

  Widget _wrapWithSwipe(Widget child, {required bool vertical}) {
    void onStart(Offset p) {
      setState(() => _isDragging = true);
      _handleSwipeUpdate(p, vertical);
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: vertical ? null : (d) => onStart(d.globalPosition),
      onHorizontalDragUpdate: vertical
          ? null
          : (d) => _handleSwipeUpdate(d.globalPosition, vertical),
      onHorizontalDragEnd: vertical ? null : (_) => _endDrag(),
      onHorizontalDragCancel: vertical ? null : _endDrag,
      onVerticalDragStart: !vertical ? null : (d) => onStart(d.globalPosition),
      onVerticalDragUpdate: !vertical
          ? null
          : (d) => _handleSwipeUpdate(d.globalPosition, vertical),
      onVerticalDragEnd: !vertical ? null : (_) => _endDrag(),
      onVerticalDragCancel: !vertical ? null : _endDrag,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kNavChipWideBreakpoint;
    final wrap = widget.chipWrapper;
    final chips = [
      for (var i = 0; i < widget.icons.length; i++)
        () {
          final chip = NavChip(
            key: _chipKeys[i],
            icon: widget.icons[i],
            iconSize: widget.iconSizes[i],
            label: widget.labels[i],
            selected: widget.selectedIndex == i,
            popped: _isDragging && _poppedIndexes.contains(i),
            vertical: isWide,
            onTap: () => widget.onSelected(i),
            liquid: true,
          );
          return wrap == null ? chip : wrap(i, chip);
        }(),
    ];
    // 選択色は、水が流れ込むように移す（ホームと同じ、2026-11-26）。
    final liquidEntries = [
      for (var i = 0; i < widget.icons.length; i++)
        LiquidChipEntry(
          chipKey: _chipKeys[i],
          icon: widget.icons[i],
          iconSize: widget.iconSizes[i],
        ),
    ];

    final content = Padding(
      padding: isWide
          ? const EdgeInsets.only(left: kNavChipSize + kNavChipMargin * 2)
          : const EdgeInsets.only(bottom: kNavChipSize + kNavChipMargin * 2),
      child: widget.child,
    );

    return Stack(
      children: [
        content,
        if (isWide)
          Positioned(
            left: kNavChipMargin,
            top: 0,
            bottom: 0,
            // 当たり判定をチップ自体でなく帯全体に広げる為、
            // GestureDetectorをCenterの外側に置く（ホーム画面と同じ）。
            child: _wrapWithSwipe(
              vertical: true,
              Center(
                child: NavChipBand(
                  entries: liquidEntries,
                  selectedIndex: widget.selectedIndex,
                  vertical: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < chips.length; i++) ...[
                        if (i > 0) const SizedBox(height: kNavChipGap),
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
            bottom: kNavChipMargin,
            child: _wrapWithSwipe(
              vertical: false,
              Center(
                child: NavChipBand(
                  entries: liquidEntries,
                  selectedIndex: widget.selectedIndex,
                  vertical: false,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < chips.length; i++) ...[
                        if (i > 0) const SizedBox(width: kNavChipGap),
                        chips[i],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
