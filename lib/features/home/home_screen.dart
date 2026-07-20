import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../chat/add_chat_screen.dart';
import '../chat/create_group_screen.dart';
import '../chat/talks_tab.dart';
import '../profile/profile_tab.dart';
import '../settings/settings_tab.dart';
import '../support/support_tab.dart';

const _kOrange = Color(0xFFEE7800);

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

  void _openAddChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddChatScreen(currentUser: widget.currentUser),
      ),
    );
  }

  void _openCreateGroup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateGroupScreen(currentUser: widget.currentUser),
      ),
    );
  }

  Future<void> _showAddMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_outlined),
              title: const Text('一対を始める'),
              subtitle: const Text('1対1で話す相手を追加する'),
              onTap: () {
                Navigator.of(context).pop();
                _openAddChat();
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('広場を作る'),
              subtitle: const Text('3人以上のグループを作る'),
              onTap: () {
                Navigator.of(context).pop();
                _openCreateGroup();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      TalksTab(currentUser: widget.currentUser),
      ProfileTab(currentUser: widget.currentUser),
      const SettingsTab(),
      const SupportTab(),
    ];

    final isWide = MediaQuery.sizeOf(context).width >= _kWideLayoutBreakpoint;

    final fab = _selectedIndex == 0
        ? FloatingActionButton(
            onPressed: _showAddMenu,
            backgroundColor: _kOrange,
            child: const Icon(Icons.add, color: Colors.white),
          )
        : null;

    if (isWide) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _selectedIndex == 0
                ? '${_titles[0]}（@${widget.currentUser.rhingId}）'
                : _titles[_selectedIndex],
          ),
        ),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              labelType: NavigationRailLabelType.all,
              indicatorColor: _kOrange.withValues(alpha: 0.2),
              leading: fab,
              destinations: [
                for (var i = 0; i < _titles.length; i++)
                  NavigationRailDestination(
                    icon: Icon(_icons[i]),
                    label: Text(_titles[i]),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: IndexedStack(index: _selectedIndex, children: tabs),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedIndex == 0
              ? '${_titles[0]}（@${widget.currentUser.rhingId}）'
              : _titles[_selectedIndex],
        ),
      ),
      body: IndexedStack(index: _selectedIndex, children: tabs),
      floatingActionButton: fab,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        indicatorColor: _kOrange.withValues(alpha: 0.2),
        destinations: [
          for (var i = 0; i < _titles.length; i++)
            NavigationDestination(icon: Icon(_icons[i]), label: _titles[i]),
        ],
      ),
    );
  }
}
