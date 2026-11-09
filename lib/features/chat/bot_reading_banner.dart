import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/bot.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/glass/glass_surface.dart';
import 'bot_management_popup.dart';

/// 広場の寄合に「BOTが読める」ことを常に見せるバナー（bot API、2026-11-09）。
/// 有効なBOTが1つも無ければ何も出さない（`SizedBox.shrink()`）ので、呼び出し側は
/// 常時組み込んでよい。メンバー全員に見える（BOTが読んでいることを隠さない）。
/// タップでBOTの一覧（[BotManagementPopup]）を開く。見た目は`JoinRequestBanner`と同じ。
class BotReadingBanner extends ConsumerWidget {
  const BotReadingBanner({
    super.key,
    this.group,
    this.dm,
    required this.currentUser,
  }) : assert((group == null) != (dm == null));

  /// 広場の場合。一対の場合は[dm]（どちらか一方だけ渡す）。
  final Group? group;
  final DirectMessage? dm;
  final AppUser currentUser;

  BotConversation get _conversation => dm != null
      ? BotConversation.dm(dm!.dmId)
      : BotConversation.group(group!.groupId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bots =
        ref
            .watch(_conversationBotsProvider(_conversation))
            .value
            ?.where((b) => b.status == GroupBotStatus.active)
            .toList() ??
        const <GroupBot>[];
    if (bots.isEmpty) return const SizedBox.shrink();

    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final background = isGekiga ? GekigaColors.panel : colorScheme.primary;
    final foreground = isGekiga ? GekigaColors.onPanel : colorScheme.onPrimary;

    final content = InkWell(
      onTap: () => _open(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.smart_toy_outlined, size: 18, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                (dm != null
                    ? strings.botReadingBannerDm
                    : strings.botReadingBanner)(
                  bots.map((b) => b.name).join('、'),
                ),
                style: TextStyle(color: foreground),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: foreground),
          ],
        ),
      ),
    );

    if (isGlass) {
      return GlassSurface(
        variant: GlassVariant.chrome,
        borderRadius: BorderRadius.zero,
        enableEdgeStroke: false,
        child: Material(
          color: background.withValues(alpha: 0.55),
          child: content,
        ),
      );
    }
    final borderColor = isGekiga
        ? GekigaColors.onPanel
        : colorScheme.outlineVariant;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: isGekiga ? 3 : 1),
      ),
      child: Material(color: background, child: content),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    showAppDialog<void>(
      context: context,
      builder: (_) => glassAwareDialog(
        isGlass: isGlass,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340, maxHeight: 640),
          child: BotManagementPopup(
            currentUser: currentUser,
            group: group,
            dm: dm,
          ),
        ),
      ),
    );
  }
}

/// 会話ごとのBOT一覧。[BotConversation]は値の等価性を持つ為、そのままキーにする
final _conversationBotsProvider =
    StreamProvider.family<List<GroupBot>, BotConversation>(
      (ref, conversation) =>
          ref.watch(botRepositoryProvider).watchConversationBots(conversation),
    );
