import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../widgets/gekiga/gekiga_section_header.dart';
import '../settings/account_toggle.dart';

/// 4つ目のメニューチップ「アカウント」の画面（2026-11-11）。保存したアカウントが2つ以上
/// ある時だけチップが出て、ここから切り替える。中身は設定>アカウントと同じ
/// [AccountToggle]。
class AccountTab extends ConsumerWidget {
  const AccountTab({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    // チップのすぐ上へ寄せる（片手で届くように）。横表示ではこのチップ自体を出さない。
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: GekigaSectionHeader(strings.switchAccountsSection),
              ),
              AccountToggle(strings: strings, currentUser: currentUser),
            ],
          ),
        ),
      ),
    );
  }
}
