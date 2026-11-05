import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/calendar_category.dart';
import '../../models/calendar_system.dart';
import '../../models/calendar_week_start.dart';
import '../../providers/calendar_system_provider.dart';
import '../../providers/holiday_settings_provider.dart';
import 'calendar_settings_widgets.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/popup_surface_colors.dart';
import '../../utils/color_hex.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/app_dialog.dart';

/// 予定・日程調整の種類（カテゴリ）の管理ポップアップ（2026-09-11追加、
/// 同日改修: 独立した中央寄せDialogから、設定の歯車ボタン直下に浮かべる
/// ドロップダウン形式のポップアップに変更した。`calendar_pane_view.dart`の
/// `_showDayEventsPopup`と同じ`showMenu`＋`popup_surface_colors.dart`の
/// 反転配色パターンを踏襲する（閉じるのはタップアウトのみ、×ボタンは
/// 持たない）。追加/編集/削除の確認だけは引き続き中央寄せのモーダル
/// ダイアログで行う。
class CalendarCategoryListPopup extends ConsumerWidget {
  const CalendarCategoryListPopup({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    super.key,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;

  Future<void> _showCategoryDialog(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    bool isGlass, {
    CalendarCategory? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final hexController = TextEditingController(
      text: existing != null
          ? Color(
              0xFF000000 | existing.color,
            ).toHexString().replaceFirst('#', '')
          : 'EE7800',
    );
    String? errorText;

    if (!context.mounted) return;
    final result = await showAppDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final previewColor = tryParseHexColor(hexController.text);
          void confirm() {
            if (nameController.text.trim().isEmpty) return;
            if (previewColor == null) {
              setState(() => errorText = strings.calendarCategoryColorInvalid);
              return;
            }
            Navigator.of(context).pop(true);
          }

          final title = Text(
            existing == null
                ? strings.calendarCategoryCreateDialogTitle
                : strings.calendarCategoryEditDialogTitle,
          );
          final content = SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: strings.calendarCategoryDialogNameLabel,
                  ),
                  onSubmitted: (_) => confirm(),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: previewColor ?? Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black12),
                      ),
                      child: previewColor == null
                          ? const Icon(Icons.circle_outlined, size: 18)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: hexController,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp('[0-9a-fA-F]'),
                          ),
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(
                          labelText: strings.settingsColorCode,
                          prefixText: '#',
                          hintText: 'EE7800',
                          errorText: errorText,
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => confirm(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
          final actions = [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(onPressed: confirm, child: Text(strings.save)),
          ];
          return isGlass
              ? GlassAlertDialog(
                  title: title,
                  content: content,
                  actions: actions,
                )
              : KeyboardAlertDialog(
                  title: title,
                  content: content,
                  actions: actions,
                );
        },
      ),
    );

    if (result != true) return;
    final color = tryParseHexColor(hexController.text)!.toARGB32() & 0xFFFFFF;
    final name = nameController.text.trim();
    final repository = ref.read(calendarCategoryRepositoryProvider);
    if (existing == null) {
      await repository.createCategory(
        isDm: isDm,
        conversationId: conversationId,
        roomId: roomId,
        name: name,
        color: color,
      );
    } else {
      await repository.updateCategory(
        isDm: isDm,
        conversationId: conversationId,
        roomId: roomId,
        categoryId: existing.categoryId,
        name: name,
        color: color,
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    CalendarCategory category, {
    required bool isGlass,
  }) async {
    final title = Text(strings.calendarCategoryDeleteConfirmTitle);
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(strings.cancel),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.red.shade700,
          foregroundColor: Colors.white,
        ),
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(strings.calendarCategoryDeleteConfirmButton),
      ),
    ];
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => isGlass
          ? GlassAlertDialog(title: title, actions: actions)
          : KeyboardAlertDialog(title: title, actions: actions),
    );
    if (confirmed == true) {
      await ref
          .read(calendarCategoryRepositoryProvider)
          .deleteCategory(
            isDm: isDm,
            conversationId: conversationId,
            roomId: roomId,
            categoryId: category.categoryId,
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGlass = uiStyle == AppUiStyle.glass;
    final repository = ref.watch(calendarCategoryRepositoryProvider);
    final brightness = Theme.of(context).brightness;
    final background = popupCardBackground(brightness, uiStyle);
    final foreground = popupCardForeground(brightness, uiStyle);
    final border = popupCardBorder(brightness, uiStyle);

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ConversationCalendarSettings(
            conversationId: conversationId,
            strings: strings,
            foreground: foreground,
            background: background,
          ),
          Divider(height: 24, color: foreground.withValues(alpha: 0.2)),
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.calendarCategoryListTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: foreground,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.add, color: foreground),
                onPressed: () =>
                    _showCategoryDialog(context, ref, strings, isGlass),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: StreamBuilder<List<CalendarCategory>>(
              stream: repository.watchCategories(
                isDm: isDm,
                conversationId: conversationId,
                roomId: roomId,
              ),
              builder: (context, snapshot) {
                final categories = snapshot.data ?? const <CalendarCategory>[];
                if (categories.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      strings.calendarCategoryListEmpty,
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.7),
                      ),
                    ),
                  );
                }
                return ListView(
                  shrinkWrap: true,
                  children: [
                    for (final category in categories)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 12,
                          backgroundColor: Color(0xFF000000 | category.color),
                        ),
                        title: Text(
                          category.name,
                          style: TextStyle(color: foreground),
                        ),
                        onTap: () => _showCategoryDialog(
                          context,
                          ref,
                          strings,
                          isGlass,
                          existing: category,
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: foreground),
                          onPressed: () => _confirmDelete(
                            context,
                            ref,
                            strings,
                            category,
                            isGlass: isGlass,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );

    return SizedBox(
      width: 300,
      child: Container(
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: content,
      ),
    );
  }
}

/// この語らいのカレンダーの設定（2026-11-05）。週の始まり・暦・祝日/祭日/宗教を、
/// 標準（設定>語らい>カレンダー）から変えられる。「標準に合わせる」を選ぶと上書きを消す。
/// どれも自分の画面の表示にだけ効き、ほかの人や予定の日時には影響しない。
class _ConversationCalendarSettings extends ConsumerWidget {
  const _ConversationCalendarSettings({
    required this.conversationId,
    required this.strings,
    required this.foreground,
    required this.background,
  });

  final String conversationId;
  final Strings strings;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authStateProvider).value?.uid;
    final repository = ref.read(conversationPrefsRepositoryProvider);
    final weekOverride = ref.watch(
      conversationWeekStartProvider(conversationId),
    );
    final systemOverride = ref.watch(
      conversationCalendarSystemProvider(conversationId),
    );
    final holidayOverride = ref.watch(
      conversationHolidayOverrideProvider(conversationId),
    );
    final defaultHolidays = ref.watch(holidaySettingsProvider);
    final residence = ref.watch(holidayCountryProvider).value ?? 'JP';
    final followLabel = strings.calendarSystemFollowGlobal;

    Widget title(String text) => Text(
      text,
      style: TextStyle(fontWeight: FontWeight.bold, color: foreground),
    );

    void saveHolidays(HolidaySettings value) {
      if (userId == null) return;
      repository.setHolidayOverride(
        userId: userId,
        conversationId: conversationId,
        override: value.toOverrideJson(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.calendarSettingsThisChatTitle,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: foreground,
          ),
        ),
        const SizedBox(height: 12),
        title(strings.calendarWeekStartLabel),
        const SizedBox(height: 8),
        CalendarChoiceRow<CalendarWeekStart>(
          options: weekStartOptions(
            strings,
            withDefault: true,
            defaultLabel: followLabel,
          ),
          selected: weekOverride,
          onSelected: (value) {
            if (userId == null) return;
            repository.setCalendarWeekStart(
              userId: userId,
              conversationId: conversationId,
              weekStart: value?.name,
            );
          },
          foreground: foreground,
          background: background,
        ),
        const SizedBox(height: 12),
        title(strings.calendarSystemLabel),
        const SizedBox(height: 8),
        CalendarChoiceRow<CalendarSystem>(
          options: calendarSystemOptions(
            strings,
            withDefault: true,
            defaultLabel: followLabel,
          ),
          selected: systemOverride,
          onSelected: (value) {
            if (userId == null) return;
            repository.setCalendarSystem(
              userId: userId,
              conversationId: conversationId,
              calendarSystem: value?.name,
            );
          },
          foreground: foreground,
          background: background,
        ),
        const SizedBox(height: 12),
        title(strings.holidaySettingsTitle),
        const SizedBox(height: 4),
        CalendarChoiceRow<bool>(
          options: [(value: true, label: followLabel)],
          selected: holidayOverride == null ? true : null,
          onSelected: (_) {
            if (userId == null) return;
            repository.setHolidayOverride(
              userId: userId,
              conversationId: conversationId,
              override: null,
            );
          },
          foreground: foreground,
          background: background,
        ),
        const SizedBox(height: 8),
        // チェックボックスは常に出す。操作すると、この語らいだけの値になる。
        // 「標準に変更」で上書きを消して標準の値に戻す。
        HolidayCheckboxes(
          strings: strings,
          settings: holidayOverride ?? defaultHolidays,
          residenceCountry: residence,
          onRegion: (country, enabled) {
            final current = holidayOverride ?? defaultHolidays;
            final regions = {...current.effectiveRegions(residence)};
            enabled ? regions.add(country) : regions.remove(country);
            saveHolidays(current.copyWith(regions: regions));
          },
          onObservances: (enabled) => saveHolidays(
            (holidayOverride ?? defaultHolidays).copyWith(observances: enabled),
          ),
          onReligion: (religion, enabled) {
            final current = holidayOverride ?? defaultHolidays;
            final religions = {...current.religions};
            enabled ? religions.add(religion) : religions.remove(religion);
            saveHolidays(current.copyWith(religions: religions));
          },
          foreground: foreground,
          background: background,
        ),
        const SizedBox(height: 8),
        Text(
          strings.calendarSystemNote,
          style: TextStyle(
            fontSize: 11,
            color: foreground.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
