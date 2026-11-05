import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/motion.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../gekiga/settings_tile.dart';
import 'toggle_style.dart';

/// 弾むチェックボックス（2026-11-05、Material標準の`Checkbox`の置き換え）。枠が塗りに
/// 変わり、チェックが描かれ、ポンと弾む。端末の「動きを減らす」では即切り替える。
class AppCheckbox extends ConsumerStatefulWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.onDarkSurface = false,
    this.foreground,
    this.background,
  });

  final bool value;
  final ValueChanged<bool?>? onChanged;

  /// 劇画の黒いタイルの上に置く時、白黒を反転する。
  final bool onDarkSurface;

  /// 反転配色のポップアップ（文字色[foreground]・地の色[background]）で使う時に渡す。
  /// 渡すと、スタイルの色の代わりにこの2色で描く。
  final Color? foreground;
  final Color? background;

  @override
  ConsumerState<AppCheckbox> createState() => _AppCheckboxState();
}

class _AppCheckboxState extends ConsumerState<AppCheckbox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: widget.value ? 1 : 0,
  );
  bool _focused = false;

  bool get _enabled => widget.onChanged != null;

  @override
  void didUpdateWidget(AppCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    final target = widget.value ? 1.0 : 0.0;
    if (reduceMotion(context)) {
      _c.value = target;
    } else {
      _c.animateTo(target, duration: toggleDurationFor(ref, springDuration));
    }
  }

  void _toggle() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
    widget.onChanged!(!widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.foreground;
    final bg = widget.background;
    final colors = (fg != null && bg != null)
        ? ToggleColors(
            onFill: fg,
            offFill: Colors.transparent,
            onThumb: bg,
            offThumb: fg,
            border: fg.withValues(alpha: 0.7),
            borderWidth: 1.5,
            check: fg,
          )
        : ToggleColors.of(context, ref, onDark: widget.onDarkSurface);
    final scheme = Theme.of(context).colorScheme;
    final box = AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // 弾み: 0→1の途中で少し大きくなってから戻る。
        final bump = 1 + 0.18 * math.sin(math.pi * t);
        return Transform.scale(
          scale: bump,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Color.lerp(Colors.transparent, colors.onFill, t),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _focused
                    ? scheme.onSurface
                    : Color.lerp(colors.border, colors.onFill, t)!,
                width: _focused ? 2 : colors.borderWidth,
              ),
            ),
            child: CustomPaint(
              painter: _CheckPainter(
                progress: Curves.easeOut.transform(t),
                color: colors.onThumb,
              ),
            ),
          ),
        );
      },
    );
    return Semantics(
      checked: widget.value,
      enabled: _enabled,
      onTap: _enabled ? _toggle : null,
      child: FocusableActionDetector(
        enabled: _enabled,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Opacity(opacity: _enabled ? 1 : 0.4, child: box),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.02) return;
    final path = Path()
      ..moveTo(size.width * 0.24, size.height * 0.52)
      ..lineTo(size.width * 0.43, size.height * 0.71)
      ..lineTo(size.width * 0.76, size.height * 0.30);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color;
}

/// 行全体のタップで切り替わるチェックボックス付きの行（`CheckboxListTile`の置き換え）。
class AppCheckboxListTile extends ConsumerWidget {
  const AppCheckboxListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.contentPadding,
    this.dense,
    this.controlAffinity = ListTileControlAffinity.platform,
  });

  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;
  final bool? dense;
  final ListTileControlAffinity controlAffinity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checked = value ?? false;
    final gekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final control = AppCheckbox(
      value: checked,
      onChanged: onChanged,
      onDarkSurface: gekiga,
    );
    final leading = controlAffinity == ListTileControlAffinity.leading;
    return SettingsTile(
      contentPadding: contentPadding,
      enabled: onChanged != null,
      leading: leading ? control : secondary,
      title: title,
      subtitle: subtitle,
      trailing: leading ? secondary : control,
      onTap: onChanged == null ? null : () => onChanged!(!checked),
    );
  }
}
