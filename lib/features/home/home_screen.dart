import 'package:flutter/material.dart';

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
class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const _titles = ['語らい', '身だしなみ', '設定', '運営'];
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
    final tabs = [
      TalksTab(currentUser: widget.currentUser),
      ProfileTab(currentUser: widget.currentUser),
      const SettingsTab(),
      const SupportTab(),
    ];

    final isWide = MediaQuery.sizeOf(context).width >= _kWideLayoutBreakpoint;

    final chips = [
      for (var i = 0; i < _titles.length; i++)
        _NavChip(
          icon: _icons[i],
          label: _titles[i],
          selected: _selectedIndex == i,
          onTap: () => setState(() => _selectedIndex = i),
        ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: isWide
                  ? const EdgeInsets.only(
                      left: _chipSize + _chipMargin * 2,
                    )
                  : const EdgeInsets.only(
                      bottom: _chipSize + _chipMargin * 2,
                    ),
              child: IndexedStack(index: _selectedIndex, children: tabs),
            ),
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

    return Tooltip(
      message: label,
      child: Material(
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
      ),
    );
  }
}
