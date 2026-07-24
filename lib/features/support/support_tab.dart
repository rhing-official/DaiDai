import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';

/// 運営タブ。`docs/マップ.md`のサイトマップ（ホームページのURL／お知らせ／
/// 質問フォーム）に沿った項目一覧を表示する。ホームページURLは正式なURLが
/// まだ確定していないため、いずれも準備中として案内する
/// （実装内容.mdの未実装項目を参照）。
class SupportTab extends ConsumerWidget {
  const SupportTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              _SupportTile(
                icon: Icons.link,
                title: strings.supportHomepageUrl,
                strings: strings,
              ),
              _SupportTile(
                icon: Icons.campaign_outlined,
                title: strings.supportAnnouncements,
                strings: strings,
              ),
              _SupportTile(
                icon: Icons.contact_support_outlined,
                title: strings.supportContactForm,
                strings: strings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportTile extends StatelessWidget {
  const _SupportTile({
    required this.icon,
    required this.title,
    required this.strings,
  });

  final IconData icon;
  final String title;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(strings.settingsComingSoon),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: Text(strings.settingsComingSoon),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
