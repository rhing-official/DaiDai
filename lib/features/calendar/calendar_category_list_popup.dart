import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/calendar_category.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/popup_surface_colors.dart';
import '../../utils/color_hex.dart';
import '../../widgets/glass/glass_dialog.dart';

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
    final result = await showDialog<bool>(
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
              : AlertDialog(title: title, content: content, actions: actions);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => isGlass
          ? GlassAlertDialog(title: title, actions: actions)
          : AlertDialog(title: title, actions: actions),
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
