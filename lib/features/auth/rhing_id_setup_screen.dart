import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
import '../home/home_screen.dart';

/// Rhing IDの最小設定画面。
/// 本実装（秘密の質問・2段階認証など）はフェーズ1の後続タスクで追加する。
class RhingIdSetupScreen extends ConsumerStatefulWidget {
  const RhingIdSetupScreen({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<RhingIdSetupScreen> createState() => _RhingIdSetupScreenState();
}

class _RhingIdSetupScreenState extends ConsumerState<RhingIdSetupScreen> {
  final _controller = TextEditingController();
  static final _validPattern = RegExp(r'^[a-zA-Z0-9._-]{3,20}$');

  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _submit() async {
    final rhingId = _controller.text.trim();
    if (!_validPattern.hasMatch(rhingId)) {
      setState(() {
        _errorMessage = '英数字・.・-・_のみ、3〜20文字で入力してください';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final userRepository = ref.read(userRepositoryProvider);
    try {
      final available = await userRepository.isRhingIdAvailable(rhingId);
      if (!available) {
        setState(() {
          _errorMessage = 'このRhing IDはすでに使われています';
        });
        return;
      }
      final appUser = AppUser(
        userId: widget.userId,
        rhingId: rhingId.toLowerCase(),
      );
      await userRepository.createUser(appUser);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(currentUser: appUser)),
      );
      return;
    } catch (e) {
      setState(() {
        _errorMessage = '登録に失敗しました: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rhing IDを設定')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('あなただけのRhing IDを決めてください。'),
            const Text('英数字・.・-・_のみ使用できます（大文字小文字は区別されません）。'),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Rhing ID',
                border: OutlineInputBorder(),
              ),
              onSubmitted: _isSubmitting ? null : (_) => _submit(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('決定'),
            ),
          ],
        ),
      ),
    );
  }
}
