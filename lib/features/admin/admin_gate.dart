import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
import 'admin_panel_screen.dart';

/// `/admin`（隠しルート）の入り口。管理者クレーム（[isAdminProvider]）を
/// 確認し、(a) 管理者なら[AdminPanelScreen]、(b) 非管理者なら初回管理者
/// 登録ボタン（`grantFirstAdminOnce`、最初に押した人だけが成功する）を表示
/// する（2026-08-12新設）。通常のナビゲーションからは導線を出さず、URL
/// を直接開いた場合のみ到達する想定。
class AdminGate extends ConsumerStatefulWidget {
  const AdminGate({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends ConsumerState<AdminGate> {
  bool _bootstrapping = false;
  String? _bootstrapError;

  Future<void> _bootstrap() async {
    setState(() {
      _bootstrapping = true;
      _bootstrapError = null;
    });
    try {
      final granted = await ref
          .read(userRepositoryProvider)
          .bootstrapFirstAdmin();
      if (!granted) {
        setState(() => _bootstrapError = '初回管理者登録に失敗しました。');
        return;
      }
      // カスタムクレームはIDトークンを再取得しないと反映されないため、
      // forceRefreshしてからisAdminProviderを再評価する。
      await ref.read(authRepositoryProvider).isAdmin(forceRefresh: true);
      ref.invalidate(isAdminProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _bootstrapError = '初回管理者登録に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _bootstrapping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdminAsync = ref.watch(isAdminProvider);
    return isAdminAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('エラー: $error'))),
      data: (isAdmin) {
        if (isAdmin) return AdminPanelScreen(currentUser: widget.currentUser);
        return Scaffold(
          appBar: AppBar(title: const Text('管理画面')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('権限がありません。'),
                  if (_bootstrapError != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _bootstrapError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _bootstrapping ? null : _bootstrap,
                    child: _bootstrapping
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('初回管理者として登録'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
