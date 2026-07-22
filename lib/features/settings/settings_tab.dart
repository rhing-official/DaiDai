import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/ui_style.dart';
import '../../providers/repository_providers.dart';
import '../../providers/ui_style_provider.dart';

/// 設定タブ。フェーズ1の後続タスクで用語切り替え・通知設定などを追加する。
/// 今はUIスタイル切り替えとログアウトのみ。
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);

    return ListView(
      children: [
        const ListTile(
          leading: Icon(Icons.tune),
          title: Text('用語・表示設定'),
          subtitle: Text('準備中'),
        ),
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'UIスタイル',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        RadioGroup<UiStyle>(
          groupValue: uiStyle,
          onChanged: (value) {
            if (value != null) {
              ref.read(uiStyleProvider.notifier).setStyle(value);
            }
          },
          child: const Column(
            children: [
              RadioListTile<UiStyle>(
                title: Text('DaiDai（標準）'),
                subtitle: Text('橙色基調のデフォルトスタイル'),
                value: UiStyle.daidai,
              ),
              RadioListTile<UiStyle>(
                title: Text('シンプル'),
                subtitle: Text('配色・等幅フォント・余白を抑えたミニマルなスタイル'),
                value: UiStyle.simple,
              ),
            ],
          ),
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
