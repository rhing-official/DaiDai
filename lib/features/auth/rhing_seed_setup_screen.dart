import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/app_user_preferences.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/fixed_font_theme.dart';
import '../guide/first_guide_screen.dart';
import '../home/home_screen.dart';
import 'residence_survey_screen.dart';
import '../../l10n/strings.dart';

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
  static final _validPattern = RegExp(r'^[a-zA-Z0-9._-]{1,20}$');

  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _submit() async {
    final rhingSeed = _controller.text.trim();
    if (!_validPattern.hasMatch(rhingSeed)) {
      setState(() {
        _errorMessage = ref.read(appStringsProvider).rhingSeedSetupInvalidError;
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
          _errorMessage = ref.read(appStringsProvider).rhingSeedSetupTakenError;
        });
        return;
      }
      final appUser = AppUser(
        userId: widget.userId,
        rhingSeed: rhingSeed.toLowerCase(),
        // 新規登録者には初回の使い方ガイドを出す（2026-10-17追加）。既存住人は
        // この値がnullのため出ない。
        preferences: const AppUserPreferences(guideSeen: false),
      );
      await userRepository.createUser(appUser);

      if (!mounted) return;
      // 続けて居住地アンケートを挟む（2026-10-16追加）。ここで離脱しても、
      // 次回起動時に[AuthGate]が未回答として再度出す。
      final navigator = Navigator.of(context);
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResidenceSurveyScreen(
            userId: appUser.userId,
            // この画面は置き換えで破棄されるため、先に取ったNavigatorを使う。
            onCompleted: () => navigator.pushReplacement(
              MaterialPageRoute(
                // 居住地アンケートの次に、初回の使い方ガイド（2026-10-17追加）。
                builder: (_) => FirstGuideScreen(
                  userId: appUser.userId,
                  onCompleted: () => navigator.pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => HomeScreen(currentUser: appUser),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return;
    } on StateError catch (_) {
      // `UserRepository.createUser`が既存ドキメントを検知して投げる例外
      // （2026-09-24追加）。本来この画面は新規ユーザー専用のため、ここに
      // 到達した時点で何らかの誤判定（AuthGateの取得失敗等）が起きている。
      // 詳細は日記.md参照。
      setState(() {
        _errorMessage = ref
            .read(appStringsProvider)
            .rhingSeedSetupAlreadyRegisteredError;
      });
    } catch (e) {
      setState(() {
        _errorMessage = ref
            .read(appStringsProvider)
            .rhingSeedSetupFailedTemplate(e);
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
    final strings = ref.watch(appStringsProvider);
    return FixedFontTheme(
      child: Scaffold(
        appBar: AppBar(title: Text(strings.rhingSeedSetupAppBarTitle)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(strings.rhingSeedSetupIntro),
                  Text(strings.rhingSeedSetupRules),
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
                        : Text(strings.rhingSeedSetupSubmitButton),
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
