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

/// 同じグループの中で、直前に外れたラジオの位置（2026-11-29）。選ばれたラジオが、
/// そこから丸を滑らせて来る為の受け渡し。
class _RadioSlideHub {
  static Object? group;
  static _AppRadioMarkState? from;
  static DateTime? at;
}

/// 弾むラジオボタンの見た目（2026-11-05）。選ばれると内側の丸が弾んで広がり、枠の色が
/// 変わる。選択の管理は祖先の`RadioGroup`が行う（[AppRadioListTile]が橋渡しする）。
///
/// [group]を渡すと、同じグループで直前に選ばれていたラジオから、内側の丸が滑って来る
/// （2026-11-29、「滑り」）。外れた側の丸は消え、選ばれた側の枠が色づく。最初の選択など、
/// 滑る元が無い時は、従来どおり弾んで広がる。
class AppRadioMark extends ConsumerStatefulWidget {
  const AppRadioMark({
    super.key,
    required this.selected,
    this.enabled = true,
    this.color,
    this.group,
  });

  final bool selected;
  final bool enabled;

  /// 指定すると、枠・内側の丸・輪をこの色で描く（劇画の選択行のように、行の文字色に
  /// 合わせたい時）。
  final Color? color;

  /// 同じ選択肢の組を表す印。同じ印を持つラジオの間で、丸が滑る。
  final Object? group;

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
  // 外枠の色づき: 0→1。
  late final AnimationController _ring = AnimationController(
    vsync: this,
    value: widget.selected ? 1 : 0,
  );
  // 選んだ瞬間に外へ広がって消える輪。
  late final AnimationController _pulse = AnimationController(vsync: this);
  // 滑る丸の動き。
  late final AnimationController _fly = AnimationController(vsync: this);
  OverlayEntry? _flyEntry;
  _AppRadioMarkState? _flySource;
  Offset? _flyFrom;
  ToggleColors? _colors;

  /// 滑る相手を決める印。渡されなければ、同じスクロールの領域に在るラジオ同士とみなす
  /// （劇画の行のように、`RadioGroup`を介さず置かれた時用）。
  Object? get _groupKey =>
      widget.group ?? context.findAncestorStateOfType<ScrollableState>();

  Offset? _center() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  @override
  void didUpdateWidget(AppRadioMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    final on = widget.selected;
    if (reduceMotion(context)) {
      _endFly();
      _dot.value = on ? 1 : 0;
      _ring.value = on ? 1 : 0;
      return;
    }
    final slidable = _groupKey != null;
    if (on) {
      _dot.value = 0;
      if (slidable) {
        // 外れた側の記録は、同じフレームの後に出揃うので、描画の後で滑るか決める。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !widget.selected) return;
          final from = _RadioSlideHub.from;
          final at = _RadioSlideHub.at;
          final fresh =
              at != null &&
              DateTime.now().difference(at) < const Duration(milliseconds: 400);
          if (fresh &&
              identical(_RadioSlideHub.group, _groupKey) &&
              from != null &&
              from.mounted) {
            _RadioSlideHub.from = null;
            _startFly(from);
          } else {
            _pop();
          }
        });
      } else {
        _pop();
      }
    } else {
      _endFly();
      if (slidable) {
        _RadioSlideHub.group = _groupKey;
        _RadioSlideHub.from = this;
        _RadioSlideHub.at = DateTime.now();
        _dot.value = 0;
      } else {
        _dot.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeIn,
        );
      }
      _ring.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeIn,
      );
    }
  }

  void _pop() {
    _dot.animateTo(
      1,
      duration: const Duration(milliseconds: 520),
      curve: Curves.elasticOut,
    );
    _ring.animateTo(
      1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    _pulse
      ..value = 0
      ..animateTo(
        1,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
      );
  }

  void _startFly(_AppRadioMarkState from) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      _pop();
      return;
    }
    _flySource = from;
    _flyFrom = from._center();
    _ring.animateTo(
      1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
    _flyEntry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _fly,
          builder: (context, _) {
            final to = _center();
            final colors = _colors;
            final overlayBox = overlay.context.findRenderObject();
            if (to == null || colors == null || overlayBox is! RenderBox) {
              return const SizedBox.shrink();
            }
            final t = Curves.easeInOutCubic.transform(_fly.value);
            // 出発側も毎フレーム測り直す（文字の大きさの変更などで行がずれても、
            // ずれた後の行の上を滑る）。出発側が消えたら、最後に測った位置を使う。
            final source = _flySource;
            final live = source != null && source.mounted
                ? source._center()
                : null;
            if (live != null) _flyFrom = live;
            final at = Offset.lerp(_flyFrom, to, t)!;
            final local = overlayBox.globalToLocal(at);
            // 動いている間は、少しだけ膨らむ。
            final size = 12 + 4 * math.sin(math.pi * _fly.value);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: local.dx - size / 2,
                  top: local.dy - size / 2,
                  width: size,
                  height: size,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.onFill,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    overlay.insert(_flyEntry!);
    _fly
      ..value = 0
      ..animateTo(
        1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.linear,
      ).whenComplete(() {
        if (!mounted || _flyEntry == null) return;
        _endFly();
        _dot.value = 1;
        _ring.value = 1;
      });
  }

  void _endFly() {
    _flyEntry?.remove();
    _flyEntry = null;
    if (_fly.isAnimating) _fly.stop();
  }

  @override
  void dispose() {
    _flyEntry?.remove();
    _flyEntry = null;
    _dot.dispose();
    _ring.dispose();
    _pulse.dispose();
    _fly.dispose();
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
    _colors = colors;
    return Opacity(
      opacity: widget.enabled ? 1 : 0.4,
      child: SizedBox(
        width: 34,
        height: 34,
        child: AnimatedBuilder(
          animation: Listenable.merge([_dot, _ring, _pulse]),
          builder: (context, _) {
            final v = _dot.value;
            final t = _ring.value.clamp(0.0, 1.0);
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
                        color: colors.onFill.withValues(
                          alpha: v.clamp(0.0, 1.0),
                        ),
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
      group: registry,
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
