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

  @override
  Widget build(BuildContext context) {
    final tabs = [
      TalksTab(currentUser: widget.currentUser),
      ProfileTab(currentUser: widget.currentUser),
      const SettingsTab(),
      const SupportTab(),
    ];

    final isWide = MediaQuery.sizeOf(context).width >= _kWideLayoutBreakpoint;

    if (isWide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              SizedBox(
                width: 88,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < _titles.length; i++)
                      _RailItem(
                        icon: _icons[i],
                        label: _titles[i],
                        selected: _selectedIndex == i,
                        onTap: () => setState(() => _selectedIndex = i),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: IndexedStack(index: _selectedIndex, children: tabs),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _selectedIndex, children: tabs)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        destinations: [
          for (var i = 0; i < _titles.length; i++)
            NavigationDestination(icon: Icon(_icons[i]), label: _titles[i]),
        ],
      ),
    );
  }
}

/// コンピューターUI（サイドバー）用のメニュー項目。
/// NavigationRailの代わりに使い、項目同士を画面の高さいっぱいに分散配置する。
class _RailItem extends StatelessWidget {
  const _RailItem({
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
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Colors.grey[600];
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: color),
        ),
      ),
    );
  }
}
