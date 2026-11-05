import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/motion.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../gekiga/settings_tile.dart';
import 'toggle_style.dart';

/// 弾むスイッチ（2026-11-05、Material標準の`Switch`の置き換え）。押すとつまみが横に
/// 伸び、動いた先で少し行き過ぎてから戻る。トラックの色はなめらかに切り替わり、
/// オンになるとつまみの中にチェックが描かれる。つまみのドラッグでも切り替わる。
/// 端末の「動きを減らす」では即切り替える。
class AppSwitch extends ConsumerStatefulWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.onDarkSurface = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// 劇画の黒いタイルの上に置く時、白黒を反転する。
  final bool onDarkSurface;

  @override
  ConsumerState<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends ConsumerState<AppSwitch>
    with SingleTickerProviderStateMixin {
  static const _trackWidth = 52.0;
  static const _trackHeight = 30.0;
  static const _thumbRest = 22.0;
  static const _thumbPressed = 28.0;
  static const _inset = 4.0;

  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.value ? 1 : 0,
  );
  bool _pressed = false;
  bool _focused = false;
  double _dragDx = 0;

  bool get _enabled => widget.onChanged != null;

  @override
  void didUpdateWidget(AppSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _animateTo(widget.value);
  }

  void _animateTo(bool on) {
    final target = on ? 1.0 : 0.0;
    if (reduceMotion(context)) {
      _position.value = target;
      return;
    }
    _position.animateTo(
      target,
      duration: toggleDurationFor(ref, springDuration),
      curve: springCurve,
    );
  }

  void _toggle() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
    widget.onChanged!(!widget.value);
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ToggleColors.of(context, ref, onDark: widget.onDarkSurface);
    final scheme = Theme.of(context).colorScheme;
    final thumbWidth = _pressed ? _thumbPressed : _thumbRest;

    final control = AnimatedBuilder(
      animation: _position,
      builder: (context, _) {
        final v = _position.value;
        final t = v.clamp(0.0, 1.0);
        final travel = _trackWidth - _inset * 2 - thumbWidth;
        return Container(
          width: _trackWidth,
          height: _trackHeight,
          decoration: BoxDecoration(
            color: Color.lerp(colors.offFill, colors.onFill, t),
            borderRadius: BorderRadius.circular(_trackHeight / 2),
            border: Border.all(
              color: _focused
                  ? scheme.onSurface
                  : Color.lerp(colors.border, colors.onFill, t)!,
              width: _focused ? 2 : colors.borderWidth,
            ),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                left: _inset - colors.borderWidth + travel * v,
                top: (_trackHeight - 22) / 2 - colors.borderWidth,
                width: thumbWidth,
                height: 22,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.lerp(colors.offThumb, colors.onThumb, t),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: CustomPaint(
                    painter: _CheckPainter(progress: t, color: colors.check),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    return Semantics(
      toggled: widget.value,
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
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: _toggle,
          onHorizontalDragStart: _enabled
              ? (_) => setState(() {
                  _pressed = true;
                  _dragDx = 0;
                })
              : null,
          onHorizontalDragUpdate: _enabled
              ? (d) => _dragDx += d.delta.dx
              : null,
          onHorizontalDragEnd: _enabled
              ? (_) {
                  setState(() => _pressed = false);
                  if (_dragDx > 4 && !widget.value) _toggle();
                  if (_dragDx < -4 && widget.value) _toggle();
                }
              : null,
          child: Opacity(opacity: _enabled ? 1 : 0.4, child: control),
        ),
      ),
    );
  }
}

/// つまみの中に描くチェック。[progress]が0→1で線が描かれていく。
class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.02) return;
    final path = Path()
      ..moveTo(size.width * 0.28, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.68)
      ..lineTo(size.width * 0.72, size.height * 0.34);
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

/// 行全体のタップで切り替わるスイッチ付きの行（`SwitchListTile`の置き換え）。
class AppSwitchListTile extends ConsumerWidget {
  const AppSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.contentPadding,
    this.dense,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;
  final bool? dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 劇画は黒いブロックで描く（[SettingsTile]）。黒地の上なので白黒を反転する。
    final gekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    return SettingsTile(
      contentPadding: contentPadding,
      enabled: onChanged != null,
      leading: secondary,
      title: title,
      subtitle: subtitle,
      trailing: AppSwitch(
        value: value,
        onChanged: onChanged,
        onDarkSurface: gekiga,
      ),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}
