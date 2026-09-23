import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/fixed_font_theme.dart';
import '../home/home_screen.dart';

/// Rhing Seedの最小設定画面。
/// 本実装（秘密の質問・2段階認証など）はフェーズ1の後続タスクで追加する。
class RhingSeedSetupScreen extends ConsumerStatefulWidget {
  const RhingSeedSetupScreen({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<RhingSeedSetupScreen> createState() =>
      _RhingSeedSetupScreenState();
}

class _RhingSeedSetupScreenState extends ConsumerState<RhingSeedSetupScreen> {
  final _controller = TextEditingController();
  static final _validPattern = RegExp(r'^[a-zA-Z0-9._-]{3,20}$');

  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _submit() async {
    final rhingSeed = _controller.text.trim();
    if (!_validPattern.hasMatch(rhingSeed)) {
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
      final available = await userRepository.isRhingSeedAvailable(rhingSeed);
      if (!available) {
        setState(() {
          _errorMessage = 'このRhing Seedはすでに使われています';
        });
        return;
      }
      final appUser = AppUser(
        userId: widget.userId,
        rhingSeed: rhingSeed.toLowerCase(),
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
    return FixedFontTheme(
      child: Scaffold(
        appBar: AppBar(title: const Text('Rhing Seedを設定')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('あなただけのRhing Seedを決めてください。'),
                  const Text('英数字・.・-・_のみ使用できます（大文字小文字は区別されません）。'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: 'Rhing Seed',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: _isSubmitting ? null : (_) => _submit(),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox.shrink()
                        : const Text('決定'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
