import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../widgets/gekiga/gekiga_section_header.dart';
import 'account_toggle.dart';

export 'account_toggle.dart' show switchAccountFailureMessage;

/// 設定>アカウントの「アカウントの切り替え」（2026-11-11、極みの特典、当面はWebだけ）。
/// この端末に保存したアカウントを切り替えスイッチ（[AccountToggle]）で並べる。
/// 設計は`文書/複数アカウント.md`。
class AccountSwitcherSection extends ConsumerWidget {
  const AccountSwitcherSection({
    required this.strings,
    required this.currentUser,
    super.key,
  });

  final Strings strings;
  final AppUser currentUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 当面はWebだけ（他のプラットフォームは、再読み込みの代わりが未実装）。
    if (!kIsWeb) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: GekigaSectionHeader(strings.switchAccountsSection),
        ),
        AccountToggle(strings: strings, currentUser: currentUser),
        const SizedBox(height: 8),
      ],
    );
  }
}
