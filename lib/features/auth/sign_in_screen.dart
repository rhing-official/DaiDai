import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/repository_providers.dart';
import '../../repositories/auth_repository.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _isSigningIn = false;
  String? _errorMessage;

  Future<void> _signIn(
    Future<dynamic> Function(AuthRepository) signIn,
  ) async {
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });
    try {
      await signIn(ref.read(authRepositoryProvider));
    } catch (e) {
      setState(() {
        _errorMessage = 'ログインに失敗しました: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'DaiDai',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('整う、守る、私に馴染む。'),
                const SizedBox(height: 32),
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                ],
                ElevatedButton(
                  onPressed: _isSigningIn
                      ? null
                      : () => _signIn((repo) => repo.signInWithGoogle()),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                  child: _isSigningIn
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Googleでログイン'),
                ),
                // Appleでのログインは、Apple Developer Program（有料）側でのService ID/
                // 秘密鍵の設定が済むまで実際には使えないため、その設定を行うまでUIから
                // 非表示にしている。AuthRepository.signInWithApple()自体は実装済みなので、
                // 設定が完了したらボタンを復活させるだけでよい。
              ],
            ),
          ),
        ),
      ),
    );
  }
}
