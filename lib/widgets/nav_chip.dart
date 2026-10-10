import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../theme/gekiga/gekiga_colors.dart';
import 'gekiga/gekiga_badge.dart';
import 'glass/glass_surface.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final background = selected ? colorScheme.primary : colorScheme.surface;
    final foreground = selected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    // popped中は帯から浮き出させ、指を離す（popped=falseに戻る）と
    // AnimatedSlideが規定位置までスライドして戻す。
    final offset = popped
        ? (vertical ? const Offset(0.35, 0) : const Offset(0, -0.35))
        : Offset.zero;

    // 劇画スタイルは他のメニューチップ（GekigaMenuTile/GekigaPanelBox）と
    // 同じ「選択中=白地黒字、非選択中=黒地白字」の規則に統一する
    // （2026-08-04変更。以前は選択中のみアクセントカラー塗りのバッジだったが、
    // アクセントカラーは劇画UI選択中は変更不可にしたため、この画面だけ
    // 固定色になったアクセントカラーが残るのは一貫しない）。
    final chip = isGekiga
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
                  color: selected ? GekigaColors.onPanel : GekigaColors.panel,
                  seed: icon.hashCode,
                  invert: selected,
                  child: Icon(
                    icon,
                    size: iconSize,
                    color: selected ? GekigaColors.panel : GekigaColors.onPanel,
                  ),
                ),
              ),
            ),
          )
        : isGlass
        ? GlassSurface(
            variant: GlassVariant.chrome,
            borderRadius: BorderRadius.circular(kNavChipSize / 2),
            child: Material(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.45)
                  : Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
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
            ),
          )
        : Material(
            color: background,
            shape: const CircleBorder(),
            elevation: selected ? 8 : 4,
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
        child: chip,
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
  /// 開いている間に背後でタブが切り替わらないようにするため）。
  final bool Function()? isSwipeBlocked;

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
    final chips = [
      for (var i = 0; i < widget.icons.length; i++)
        NavChip(
          key: _chipKeys[i],
          icon: widget.icons[i],
          iconSize: widget.iconSizes[i],
          label: widget.labels[i],
          selected: widget.selectedIndex == i,
          popped: _isDragging && _poppedIndexes.contains(i),
          vertical: isWide,
          onTap: () => widget.onSelected(i),
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
            // 当たり判定をチップ自体でなく帯全体に広げるため、
            // GestureDetectorをCenterの外側に置く（ホーム画面と同じ）。
            child: _wrapWithSwipe(
              vertical: true,
              Center(
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
          )
        else
          Positioned(
            left: 0,
            right: 0,
            bottom: kNavChipMargin,
            child: _wrapWithSwipe(
              vertical: false,
              Center(
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
      ],
    );
  }
}
