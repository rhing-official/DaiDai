import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/group_call_banner_dismissals.dart';
import '../../providers/group_call_providers.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/glass/glass_surface.dart';
import '../call/active_call_session.dart';

/// 広場の語らい上部に出す「通話中です。タップして参加」バナー（2026-10-21追加）。
/// その広場に進行中の通話があり、自分がまだ参加していない時、語らいを開くたびに
/// **×で閉じるまで**出す（通話が始まった時にアプリを開いていなかった場合や、
/// アプリ全体の着信バナーを閉じた後でも、語らいから参加できるようにする）。
/// 通話が終われば自動で消える。PC・モバイルとも同じ。見た目は[JoinRequestBanner]・
/// `ChatTaskBanner`と同じ（劇画は白黒、フラット・ガラスはアクセントカラー）。
class GroupCallJoinBanner extends ConsumerWidget {
  const GroupCallJoinBanner({
    required this.groupId,
    required this.onJoin,
    super.key,
  });

  final String groupId;

  /// タップで通話に参加する（通話の種別は進行中の通話のものを使う）。
  final void Function(bool isVideo) onJoin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(activeGroupCallProvider(groupId)).value;
    final session = ref.watch(activeCallSessionProvider);
    final joinedId = session is GroupCallSession ? session.groupCallId : null;
    final show = shouldShowGroupCallBanner(
      activeGroupCallId: call?.groupCallId,
      joinedGroupCallId: joinedId,
      dismissedIds: ref.watch(groupCallBannerDismissalsProvider),
    );
    if (!show || call == null) return const SizedBox.shrink();

    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final background = isGekiga ? GekigaColors.panel : colorScheme.primary;
    final foreground = isGekiga ? GekigaColors.onPanel : colorScheme.onPrimary;

    final content = InkWell(
      onTap: () => onJoin(call.isVideo),
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
        child: Row(
          children: [
            Icon(
              call.isVideo ? Icons.videocam : Icons.call,
              size: 18,
              color: foreground,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.groupCallInProgressBannerLabel(call.isVideo),
                style: TextStyle(color: foreground),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 20, color: foreground),
              onPressed: () => ref
                  .read(groupCallBannerDismissalsProvider.notifier)
                  .dismiss(call.groupCallId),
            ),
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
}
