import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/motion.dart';
import '../gekiga/settings_tile.dart';
import 'toggle_style.dart';

/// 弾むラジオボタンの見た目（2026-11-05）。選ばれると内側の丸が弾んで広がり、枠の色が
/// 変わる。選択の管理は祖先の`RadioGroup`が行う（[AppRadioListTile]が橋渡しする）。
class AppRadioMark extends ConsumerStatefulWidget {
  const AppRadioMark({
    super.key,
    required this.selected,
    this.enabled = true,
    this.color,
  });

  final bool selected;
  final bool enabled;

  /// 指定すると、枠・内側の丸・輪をこの色で描く（劇画の選択行のように、行の文字色に
  /// 合わせたい時）。
  final Color? color;

  @override
  ConsumerState<AppRadioMark> createState() => _AppRadioMarkState();
}

class _AppRadioMarkState extends ConsumerState<AppRadioMark>
    with TickerProviderStateMixin {
  // 内側の丸: 0→1。選ぶ時は`elasticOut`でぷるんと揺れ、外す時は素早く縮む。
  late final AnimationController _dot = AnimationController(
    vsync: this,
    value: widget.selected ? 1 : 0,
  );
  // 選んだ瞬間に外へ広がって消える輪。
  late final AnimationController _pulse = AnimationController(vsync: this);

  @override
  void didUpdateWidget(AppRadioMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    final on = widget.selected;
    if (reduceMotion(context)) {
      _dot.value = on ? 1 : 0;
      return;
    }
    if (on) {
      _dot.value = 0;
      _dot.animateTo(
        1,
        duration: const Duration(milliseconds: 520),
        curve: Curves.elasticOut,
      );
      _pulse
        ..value = 0
        ..animateTo(
          1,
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeOutCubic,
        );
    } else {
      _dot.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeIn,
      );
    }
  }

  @override
  void dispose() {
    _dot.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = ToggleColors.of(context, ref);
    final fixed = widget.color;
    final colors = fixed == null
        ? base
        : ToggleColors(
            onFill: fixed,
            offFill: Colors.transparent,
            onThumb: fixed,
            offThumb: fixed,
            border: fixed,
            borderWidth: base.borderWidth,
            check: fixed,
          );
    return Opacity(
      opacity: widget.enabled ? 1 : 0.4,
      child: SizedBox(
        width: 34,
        height: 34,
        child: AnimatedBuilder(
          animation: Listenable.merge([_dot, _pulse]),
          builder: (context, _) {
            final v = _dot.value;
            final t = v.clamp(0.0, 1.0);
            final pulse = _pulse.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                // 広がって消える輪。
                if (pulse > 0 && pulse < 1)
                  Container(
                    width: 22 + 12 * pulse,
                    height: 22 + 12 * pulse,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.onFill.withValues(
                          alpha: 0.7 * (1 - pulse),
                        ),
                        width: 3 * (1 - pulse) + 0.5,
                      ),
                    ),
                  ),
                // 外枠: 選ぶと色が変わり、ふくらんで戻る。
                Transform.scale(
                  scale: 1 + 0.22 * math.sin(math.pi * t),
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.onFill.withValues(alpha: 0.14 * t),
                      border: Border.all(
                        color: Color.lerp(colors.border, colors.onFill, t)!,
                        width: colors.borderWidth + 0.8 * t,
                      ),
                    ),
                    child: Container(
                      width: 12 * v.clamp(0.0, 1.6),
                      height: 12 * v.clamp(0.0, 1.6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.onFill.withValues(alpha: t),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// `RadioGroup<T>`の中で使う、行全体のタップで選べるラジオ付きの行
/// （`RadioListTile`の置き換え）。
class AppRadioListTile<T> extends ConsumerWidget {
  const AppRadioListTile({
    super.key,
    required this.value,
    this.title,
    this.subtitle,
    this.secondary,
    this.contentPadding,
    this.dense,
    this.controlAffinity = ListTileControlAffinity.platform,
    this.enabled = true,
  });

  final T value;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;
  final bool? dense;

  /// 互換の為に残している引数。ラジオは全てのUIスタイルで左端に置く（2026-11-05）。
  final ListTileControlAffinity controlAffinity;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = RadioGroup.maybeOf<T>(context);
    final selected = registry != null && registry.groupValue == value;
    final active = enabled && registry != null;
    final gekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    // 劇画は選択中=白地黒文字・未選択=黒地白文字のブロック。ラジオは行の文字色に合わせる。
    final control = AppRadioMark(
      selected: selected,
      enabled: active,
      color: gekiga
          ? (selected ? GekigaColors.panel : GekigaColors.onPanel)
          : null,
    );
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: SettingsTile(
        contentPadding: contentPadding,
        selected: gekiga && selected,
        enabled: active,
        leading: control,
        title: title,
        subtitle: subtitle,
        trailing: secondary,
        onTap: active
            ? () {
                HapticFeedback.selectionClick();
                registry.onChanged(value);
              }
            : null,
      ),
    );
  }
}
