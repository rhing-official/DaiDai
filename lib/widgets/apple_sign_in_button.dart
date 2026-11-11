import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/strings.dart';
import 'branded_block_button.dart';

/// 「Appleでサインイン」ボタン（2026-11-12追加）。Googleのボタン（[GoogleSignInButton]）と
/// 同じ見た目の共通部品[BrandedBlockButton]を使い、Appleのロゴ（`Icons.apple`）を付ける。
/// 文言はAppleのガイドラインの表記（「Appleでサインイン」）に合わせる。
class AppleSignInButton extends ConsumerWidget {
  const AppleSignInButton({
    required this.onPressed,
    this.loading = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BrandedBlockButton(
      onPressed: onPressed,
      loading: loading,
      icon: const Icon(Icons.apple, size: 20),
      label: ref.watch(appStringsProvider).signInWithAppleButton,
    );
  }
}
