import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../chat/add_chat_screen.dart';
import '../chat/create_group_screen.dart';
import '../chat/talks_tab.dart';
import '../profile/profile_tab.dart';
import '../settings/settings_tab.dart';
import '../support/support_tab.dart';

const _kOrange = Color(0xFFEE7800);

/// ホーム画面。語らい・身だしなみ・設定・運営の4タブで構成される。
class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const _titles = ['語らい', '身だしなみ', '設定', '運営'];

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
              title: const Text('縁側を始める'),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedIndex == 0
              ? '${_titles[0]}（@${widget.currentUser.rhingId}）'
              : _titles[_selectedIndex],
        ),
      ),
      body: IndexedStack(index: _selectedIndex, children: tabs),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: _showAddMenu,
              backgroundColor: _kOrange,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        indicatorColor: _kOrange.withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.forum_outlined), label: '語らい'),
          NavigationDestination(icon: Icon(Icons.face_outlined), label: '身だしなみ'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: '設定'),
          NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            label: '運営',
          ),
        ],
      ),
    );
  }
}
