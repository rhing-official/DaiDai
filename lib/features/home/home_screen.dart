import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../chat/talks_tab.dart';
import '../profile/profile_tab.dart';
import '../settings/settings_tab.dart';
import '../support/support_tab.dart';

/// サイドバー/下部ナビの切り替えしきい値。Material Design 3の
/// medium windowサイズクラス（600dp）を採用する。
const _kWideLayoutBreakpoint = 600.0;

/// ホーム画面。語らい・身だしなみ・設定・運営の4タブで構成される。
/// 画面幅に応じて、コンピューターUI（サイドバー）とモバイルUI（下部ナビ）を切り替える。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  // スワイプでのタブ切り替えは指を離した瞬間の速度でのみ判定する
  // （ドラッグ中に逐次判定すると、各タブ内の横スクロール要素との
  // ジェスチャー競合が起きやすいため）。
  static const _kSwipeVelocityThreshold = 300.0;

  void _handleHorizontalDragEnd(DragEndDetails details, int tabCount) {
    // showDialog/showGeneralDialog/showMenu等のポップアップはNavigatorに
    // ルートとして積まれるため、開いている間はHomeScreen自身のルートが
    // isCurrent=falseになる。ここで弾かないと、開いたポップアップの背後で
    // タブが切り替わってしまい、以前の実装が「一貫して動作しない」原因に
    // なっていた（ポップアップの種類によってバリアの有無・挙動が異なり、
    // スワイプが素通りするものとしないものが混在していたため）。
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < _kSwipeVelocityThreshold) return;
    setState(() {
      if (velocity < 0) {
        _selectedIndex = (_selectedIndex + 1).clamp(0, tabCount - 1);
      } else {
        _selectedIndex = (_selectedIndex - 1).clamp(0, tabCount - 1);
      }
    });
  }

  static const _icons = [
    Icons.forum_outlined,
    Icons.face_outlined,
    Icons.settings_outlined,
    Icons.support_agent_outlined,
  ];

  static const _chipSize = 56.0;
  static const _chipGap = 16.0;
  static const _chipMargin = 16.0;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final titles = [
      strings.navTalk,
      strings.navProfile,
      strings.navSettings,
      strings.navSupport,
    ];

    final tabs = [
      TalksTab(currentUser: widget.currentUser),
      ProfileTab(currentUser: widget.currentUser),
      SettingsTab(currentUser: widget.currentUser),
      const SupportTab(),
    ];

    final isWide = MediaQuery.sizeOf(context).width >= _kWideLayoutBreakpoint;

    final chips = [
      for (var i = 0; i < titles.length; i++)
        _NavChip(
          icon: _icons[i],
          label: titles[i],
          selected: _selectedIndex == i,
          onTap: () => setState(() => _selectedIndex = i),
        ),
    ];

    // 本文全体を覆うGestureDetectorで横スワイプをタブ切り替えとして扱う。
    // ドラッグ中は判定せずEndイベントの速度のみで判定し（_handleHorizontalDragEnd
    // 参照）、ポップアップ表示中は反応しないようにすることで、以前あった
    // オーバーレイとのジェスチャー競合を避けている。各タブが持つ「戻る」操作
    // （設定・身だしなみ・運営の狭い画面でのドリルダウン、go_routerでpushした
    // 各画面）用の個別のスワイプバック（[SwipeBackDetector]）とは独立している。
    final content = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) =>
          _handleHorizontalDragEnd(details, tabs.length),
      child: Padding(
        padding: isWide
            ? const EdgeInsets.only(
                left: _chipSize + _chipMargin * 2,
              )
            : const EdgeInsets.only(
                bottom: _chipSize + _chipMargin * 2,
              ),
        child: IndexedStack(index: _selectedIndex, children: tabs),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            content,
            if (isWide)
              Positioned(
                left: _chipMargin,
                top: 0,
                bottom: 0,
                child: Center(
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
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: _chipMargin,
                child: Center(
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
          ],
        ),
      ),
    );
  }
}

/// メニューバーを使わず、タブ切り替えを1つずつ独立した丸いチップで表す。
/// 選択中はアクセントカラーで塗り、常に浮いて見えるよう影を付ける。
class _NavChip extends StatelessWidget {
  const _NavChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = selected ? colorScheme.primary : colorScheme.surface;
    final foreground = selected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    return Material(
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
  }
}
