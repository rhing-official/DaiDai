import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/guide_content.dart';
import '../../l10n/strings.dart';
import '../../l10n/tutorial_content.dart';
import '../../providers/app_locale_provider.dart';
import 'tutorial/tutorial_controller.dart';

/// 設定＞運営＞使い方ガイドの一覧（2026-10-17追加）。機能ごとの項目を並べ、
/// 末尾に初回の説明をもう一度見る行を置く。項目を押すと、説明のページは挟まず
/// その場でガイド（実際に操作して覚える）が始まる。台本がまだ無い項目は
/// 「準備中」と伝えるだけ（ハリボテ、台本ができ次第順次追加する）。
class GuideTopicListPage extends ConsumerWidget {
  const GuideTopicListPage({required this.onReplayFirst, super.key});

  final VoidCallback onReplayFirst;

  void _open(BuildContext context, WidgetRef ref, GuideTopic topic) {
    final script = tutorialScriptOf(topic.id);
    if (script == null) {
      final locale = ref.read(appLocaleProvider);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(guideComingSoon.of(locale))));
      return;
    }
    // ガイド専用ルートを今の画面の上に開いて始める（今の画面は下に残り、
    // ガイドを終えるとそのまま戻れる）。
    ref.read(tutorialControllerProvider.notifier).start(script);
    context.push(script.stageRoute);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final locale = ref.watch(appLocaleProvider);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(strings.guideListIntro),
        ),
        for (final topic in guideTopics)
          ListTile(
            key: ValueKey('guide-topic-${topic.id}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(topic.icon),
            title: Text(topic.titleOf(locale)),
            subtitle: Text(topic.summaryOf(locale)),
            onTap: () => _open(context, ref, topic),
          ),
        const Divider(height: 24),
        ListTile(
          key: const ValueKey('guide-replay-first'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: const Icon(Icons.replay),
          title: Text(strings.guideReplayFirst),
          onTap: onReplayFirst,
        ),
      ],
    );
  }
}
