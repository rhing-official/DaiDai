import 'package:flutter/material.dart';

import '../../l10n/holiday_data.dart';
import '../../models/calendar_system.dart';
import '../../widgets/app_dialog.dart';

/// 祝日・祭日・宗教上の祝日をタップした時のポップアップ（2026-11-06）。
/// 画像は`assets/holidays/<kind>_<id>.webp（idの「:」は「_」に置換）`があれば出し、無ければ画像欄ごと出さない。
Future<void> showHolidayDetailDialog(
  BuildContext context, {
  required HolidayEntry entry,
  required DateTime day,
  required CalendarSystem calendarSystem,
  required String localeCode,
  required String kindLabel,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return AlertDialog(
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  holidayImagePath(entry),
                  width: 220,
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                entry.nameFor(localeCode),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                kindLabel,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(formatDayTitle(calendarSystem, day, localeCode)),
            ],
          ),
        ),
      );
    },
  );
}

/// 祝日・祭日の画像のアセットパス。
String holidayImagePath(HolidayEntry entry) =>
    'assets/holidays/${entry.kind.name}_${entry.id.replaceAll(':', '_')}.webp';
