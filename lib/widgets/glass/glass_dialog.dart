import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// [AlertDialog]と同じ形（title/content/actions）を持つガラスUI版ダイアログ。
/// 呼び出し側は`isGlass ? GlassAlertDialog(...) : AlertDialog(...)`という
/// 三項分岐で既存の`AlertDialog`呼び出しをそのまま差し替えられる。
class GlassAlertDialog extends StatelessWidget {
  const GlassAlertDialog({
    this.title,
    this.content,
    this.actions,
    this.scrollable = false,
    super.key,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget body = Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            DefaultTextStyle(
              style: textTheme.titleLarge ?? const TextStyle(),
              child: title!,
            ),
          if (title != null && content != null) const SizedBox(height: 16),
          if (content != null)
            DefaultTextStyle(
              style: textTheme.bodyMedium ?? const TextStyle(),
              child: content!,
            ),
        ],
      ),
    );

    if (scrollable) {
      body = SingleChildScrollView(child: body);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassSurface(
        variant: GlassVariant.floating,
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: body),
            if (actions != null && actions!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions!.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions![i],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
