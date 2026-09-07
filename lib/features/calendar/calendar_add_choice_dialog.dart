import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/swipe_gestures.dart';

/// カレンダーの日付クリック時に「予定追加」か「日程調整」かを選ばせる
/// ダイアログ（2026-09-05追加、`calendar_pane_view.dart`から呼ばれる）。
enum CalendarAddChoice { event, scheduleCoordination }

/// `talks_tab.dart`の`_showAddMenu`（「＋」ボタンから開く「一対を始める／
/// 広場を作る」の2択）と同じ、中央の区切り線で左右2分割した大きめカード
/// デザインに揃えた（2026-09-07変更、以前は`AlertDialog`にボタン2つを
/// 並べただけの簡素なポップアップだった）。`_AddMenuOption`はprivateの
/// ため、同構成の`_AddChoiceOption`をこのファイル内に個別に用意している。
Future<CalendarAddChoice?> showCalendarAddChoiceDialog(
  BuildContext context,
) async {
  final container = ProviderScope.containerOf(context);
  final isGlass = container.read(appUiStyleProvider) == AppUiStyle.glass;
  final strings = container.read(appStringsProvider);
  return showGeneralDialog<CalendarAddChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: strings.calendarAddChoiceDialogTitle,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final colorScheme = Theme.of(dialogContext).colorScheme;
      final menuContent = SwipeDownToDismiss(
        onDismiss: () => Navigator.of(dialogContext).pop(),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _AddChoiceOption(
                  icon: Icons.event_outlined,
                  title: strings.calendarAddChoiceEventOption,
                  subtitle: strings.calendarAddChoiceEventSubtitle,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(20),
                  ),
                  onTap: () =>
                      Navigator.of(dialogContext).pop(CalendarAddChoice.event),
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colorScheme.outlineVariant,
              ),
              Expanded(
                child: _AddChoiceOption(
                  icon: Icons.event_available_outlined,
                  title: strings.calendarAddChoiceCoordinationOption,
                  subtitle: strings.calendarAddChoiceCoordinationSubtitle,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(20),
                  ),
                  onTap: () => Navigator.of(
                    dialogContext,
                  ).pop(CalendarAddChoice.scheduleCoordination),
                ),
              ),
            ],
          ),
        ),
      );
      final content = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: menuContent,
      );
      return Center(
        child: Dialog(
          backgroundColor: isGlass ? Colors.transparent : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: isGlass
              ? GlassSurface(
                  variant: GlassVariant.floating,
                  borderRadius: BorderRadius.circular(20),
                  child: content,
                )
              : content,
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      // 少し行き過ぎてから戻る、弾むような「ポップ」演出（_showAddMenuと同じ）。
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: curved, child: child),
      );
    },
  );
}

/// ポップアップの左右どちらか半分を占める、大きめのタップ可能領域
/// （`talks_tab.dart`の`_AddMenuOption`と同構成）。
class _AddChoiceOption extends StatelessWidget {
  const _AddChoiceOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.borderRadius,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: borderRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
