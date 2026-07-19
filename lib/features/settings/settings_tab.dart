import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/repository_providers.dart';

/// 設定タブ。フェーズ1の後続タスクで用語切り替え・通知設定などを追加する。
/// 今はログアウトのみ。
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        const ListTile(
          leading: Icon(Icons.tune),
          title: Text('用語・表示設定'),
          subtitle: Text('準備中'),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text('ログアウト', style: TextStyle(color: Colors.red)),
          onTap: () => ref.read(authRepositoryProvider).signOut(),
        ),
      ],
    );
  }
}
