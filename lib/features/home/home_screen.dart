import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/gekiga/gekiga_badge.dart';
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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  // なぞっている間だけ選択中チップを飛び出させるためのフラグ（2026-07-29追加）。
  // ドラッグ開始でtrue、指を離す/キャンセルでfalseに戻す。
  bool _isDragging = false;

  // なぞっている間、飛び出させるチップのindex集合。指がチップの真上にある
  // 間は1件だけ、チップ同士の隙間の上にある間は前後2件になる
  // （2026-07-29追加）。色（選択中の塗り）は_selectedIndexだけに紐付ける
  // ため、隙間で両方飛び出していても色が付くのは元々選択されていた方のみ。
  Set<int> _poppedIndexes = {};

  // チップの帯を指でなぞっている間、今指が乗っているチップの実際の描画位置を
  // 判定するために使う（2026-07-29変更、以前はフリック時の速度だけで隣へ
  // 1段階移動する実装だった。指を離すまで連続的に、語らいから設定まで
  // 1回のドラッグで移動できるようにするため、位置ベースの追従に変更）。
  late final List<GlobalKey> _chipKeys = List.generate(3, (_) => GlobalKey());

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
    // どのチップの上でもない＝隙間。隙間を挟む前後2つのチップを両方
    // 飛び出させる（選択自体は変えない）。
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

  /// チップの帯をドラッグしている間、逐次呼ぶ（Start・Updateの両方から）。
  /// 指が乗っているチップへその場でタブを切り替え、飛び出させるチップの
  /// 集合を更新する。
  void _handleSwipeUpdate(Offset globalPosition, int tabCount, bool vertical) {
    // showDialog/showGeneralDialog/showMenu等のポップアップはNavigatorに
    // ルートとして積まれるため、開いている間はHomeScreen自身のルートが
    // isCurrent=falseになる。ここで弾かないと、開いたポップアップの背後で
    // タブが切り替わってしまい、以前の実装が「一貫して動作しない」原因に
    // なっていた（ポップアップの種類によってバリアの有無・挙動が異なり、
    // スワイプが素通りするものとしないものが混在していたため）。
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final hit = _hitTestChips(globalPosition, vertical);
    final selectionChanged =
        hit.hovered != null && hit.hovered != _selectedIndex;
    final poppedChanged = !setEquals(hit.popped, _poppedIndexes);
    if (!selectionChanged && !poppedChanged) return;
    setState(() {
      _poppedIndexes = hit.popped;
      if (selectionChanged)
        _selectedIndex = hit.hovered!.clamp(0, tabCount - 1);
    });
  }

  static const _icons = [
    Icons.forum_outlined,
    Icons.face_outlined,
    Icons.settings_outlined,
  ];

  static const _chipSize = 56.0;
  static const _chipGap = 16.0;
  static const _chipMargin = 16.0;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final titles = [strings.navTalk, strings.navProfile, strings.navSettings];

    final tabs = [
      TalksTab(currentUser: widget.currentUser),
      ProfileTab(currentUser: widget.currentUser),
      SettingsTab(currentUser: widget.currentUser),
    ];

    final isWide = MediaQuery.sizeOf(context).width >= _kWideLayoutBreakpoint;

    final chips = [
      for (var i = 0; i < titles.length; i++)
        _NavChip(
          key: _chipKeys[i],
          icon: _icons[i],
          label: titles[i],
          selected: _selectedIndex == i,
          popped: _isDragging && _poppedIndexes.contains(i),
          vertical: isWide,
          onTap: () => setState(() => _selectedIndex = i),
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
    final content = Padding(
      padding: isWide
          ? const EdgeInsets.only(left: _chipSize + _chipMargin * 2)
          : const EdgeInsets.only(bottom: _chipSize + _chipMargin * 2),
      child: IndexedStack(index: _selectedIndex, children: tabs),
    );

    Widget wrapWithSwipe(Widget child, {required bool vertical}) {
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

      return GestureDetector(
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
      );
    }

    return Scaffold(
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
                  Center(
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
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: _chipMargin,
                child: wrapWithSwipe(
                  vertical: false,
                  Center(
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
          ],
        ),
      ),
    );
  }
}

/// メニューバーを使わず、タブ切り替えを1つずつ独立した丸いチップで表す。
/// 選択中はアクセントカラーで塗り、常に浮いて見えるよう影を付ける。
/// 劇画スタイル時は丸いチップの代わりにジグザグのバッジ意匠を使う
/// （2026-07-30、appUiStyleProviderを見るためConsumerWidget化）。
class _NavChip extends ConsumerWidget {
  const _NavChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.popped,
    required this.vertical,
    required this.onTap,
    super.key,
  });

  final IconData icon;
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
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
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
                width: _HomeScreenState._chipSize,
                height: _HomeScreenState._chipSize,
                child: GekigaBadgeShape(
                  color: selected ? GekigaColors.onPanel : GekigaColors.panel,
                  seed: icon.hashCode,
                  child: Icon(
                    icon,
                    color: selected ? GekigaColors.panel : GekigaColors.onPanel,
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
                width: _HomeScreenState._chipSize,
                height: _HomeScreenState._chipSize,
                child: Icon(icon, color: foreground),
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
