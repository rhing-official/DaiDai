import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/profile_material.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/gekiga/gekiga_text_field.dart';
import '../../widgets/glass/glass_dialog.dart';

/// 相手の呼び名を自分の画面だけで指定するダイアログ（2026-11-06）。
/// 戻り値: キャンセルは`null`、保存は入力した呼び名、取り消し（空で保存も同じ）は空文字。
/// [current]は今の指定（初期値）、[original]は相手本来の呼び名（あれば「元の呼び名」として添える）。
Future<String?> promptContactAlias(
  BuildContext context,
  Strings strings, {
  required String? current,
  required String? original,
  bool isGekiga = false,
  bool isGlass = false,
}) {
  final controller = TextEditingController(text: current ?? '');
  final formatters = [LengthLimitingTextInputFormatter(kMaxNicknameLength)];
  final title = Text(strings.contactAliasTitle);
  final field = isGekiga
      ? GekigaTextField(
          controller: controller,
          autofocus: true,
          hintText: strings.contactAliasHint,
          inputFormatters: formatters,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        )
      : TextField(
          controller: controller,
          autofocus: true,
          inputFormatters: formatters,
          decoration: InputDecoration(hintText: strings.contactAliasHint),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        );
  final content = Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      field,
      const SizedBox(height: 12),
      Text(
        strings.contactAliasDescription,
        style: const TextStyle(fontSize: 12),
      ),
      if (original != null && original.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          strings.contactAliasOriginalTemplate(original),
          style: const TextStyle(fontSize: 12),
        ),
      ],
    ],
  );
  final hasCurrent = current != null && current.isNotEmpty;
  final actions = [
    TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(strings.cancel),
    ),
    if (hasCurrent)
      TextButton(
        onPressed: () => Navigator.of(context).pop(''),
        child: Text(strings.contactAliasClear),
      ),
    FilledButton(
      onPressed: () => Navigator.of(context).pop(controller.text.trim()),
      child: Text(strings.save),
    ),
  ];
  return showAppDialog<String>(
    context: context,
    builder: (context) => isGlass
        ? ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: GlassAlertDialog(
              title: title,
              content: content,
              actions: actions,
            ),
          )
        : KeyboardAlertDialog(
            constraints: const BoxConstraints(maxWidth: 400),
            title: title,
            content: content,
            actions: actions,
          ),
  );
}
