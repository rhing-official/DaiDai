import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/accent_color_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/color_hex.dart';

/// 設定タブ。フェーズ1の後続タスクで用語切り替え・通知設定などを追加する。
/// 今はアクセントカラーの変更とログアウトのみ。
class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  late final TextEditingController _hexController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(
      text: ref.read(accentColorProvider).toHexString().replaceFirst('#', ''),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _applyHexInput() {
    final color = tryParseHexColor(_hexController.text);
    if (color == null) {
      setState(() => _errorText = '「#RRGGBB」の形式で入力してください');
      return;
    }
    setState(() => _errorText = null);
    ref.read(accentColorProvider.notifier).setColor(color);
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(accentColorProvider);

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
            'アクセントカラー',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _hexController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'カラーコード',
                    prefixText: '#',
                    hintText: '3D2EE0',
                    errorText: _errorText,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check),
                      tooltip: '適用',
                      onPressed: _applyHexInput,
                    ),
                  ),
                  onSubmitted: (_) => _applyHexInput(),
                ),
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
