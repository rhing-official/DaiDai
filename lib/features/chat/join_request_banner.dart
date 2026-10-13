import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/group.dart';
import '../../models/group_role.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/group_join_request_providers.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../utils/group_permissions.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/glass/glass_surface.dart';
import 'group_member_list_screen.dart';

/// 広場の語らい上部に出す「参加リクエストが N 件あります」バナー（2026-10-11
/// 追加）。承認できる人（長・`manageJoinRequests`権限者）にだけ表示し、
/// メッセージは作らないため寄合の全メンバーには見えない。0件・権限なしなら
/// `SizedBox.shrink()`を返すので、呼び出し側は常時組み込んでよい。タップで
/// 申請者だけのポップアップ（`GroupJoinRequestsPopup`）を開く。見た目は[ChatTaskBanner]と同じ。
class JoinRequestBanner extends ConsumerWidget {
  const JoinRequestBanner({
    super.key,
    required this.group,
    required this.currentUser,
  });

  final Group group;
  final AppUser currentUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = hasGroupPermission(
      group: group,
      userId: currentUser.userId,
      permission: GroupPermission.manageJoinRequests,
    );
    if (!canManage) return const SizedBox.shrink();
    final count =
        ref.watch(pendingJoinRequestsProvider(group.groupId)).value?.length ??
        0;
    if (count == 0) return const SizedBox.shrink();

    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final background = isGekiga ? GekigaColors.panel : colorScheme.primary;
    final foreground = isGekiga ? GekigaColors.onPanel : colorScheme.onPrimary;

    final content = InkWell(
      onTap: () => _openRequests(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.person_add_alt_1, size: 18, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.joinRequestBannerLabel(count),
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

  void _openRequests(BuildContext context, WidgetRef ref) {
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    showDialog<void>(
      context: context,
      builder: (_) => glassAwareDialog(
        isGlass: isGlass,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340, maxHeight: 640),
          child: GroupJoinRequestsPopup(currentUser: currentUser, group: group),
        ),
      ),
    );
  }
}
