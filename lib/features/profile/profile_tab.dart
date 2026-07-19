import 'package:flutter/material.dart';

import '../../models/app_user.dart';

/// 身だしなみタブ（プロフィール設定・蔵システム）。
/// フェーズ1の後続タスクで実装する。今は最小限の表示のみ。
class ProfileTab extends StatelessWidget {
  const ProfileTab({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
          const SizedBox(height: 16),
          Text('@${currentUser.rhingId}', style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 8),
          const Text('プロフィール編集・蔵機能は準備中です'),
        ],
      ),
    );
  }
}
