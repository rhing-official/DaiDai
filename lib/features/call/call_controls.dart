import 'package:flutter/material.dart';

import '../../theme/block/block_theme.dart';
import '../../theme/chalk/chalk_paint.dart';
import '../../theme/chalk/chalk_theme.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/glass/glass_colors.dart';
import '../../theme/kinari/kinari_theme.dart';
import '../../widgets/kinari_surface.dart';
import '../../widgets/gekiga/gekiga_badge.dart';
import '../../widgets/glass/glass_surface.dart';

/// 通話画面の丸いコントロールボタン（マイク・カメラ・切断など）。
/// 1対1通話（[CallScreen]）とグループ通話（[GroupCallScreen]）の両方で使う
/// （通話中のボタン列自体は[CallControlBar]が共通で組み立てる。これは
/// 個々のボタン1つ分の見た目のみを担当する）。フラット/劇画/ガラス/版画いずれの
/// スタイルにも対応する（2026-08-19、通話画面の独自UI化に伴い追加。
/// 2026-08-30にガラス分岐を追加）。
class CallRoundButton extends StatelessWidget {
  const CallRoundButton({
    required this.icon,
    required this.color,
    required this.isGekiga,
    required this.isGlass,
    this.onPressed,
    super.key,
  });

  final IconData icon;
  final Color color;
  final bool isGekiga;
  final bool isGlass;
  final VoidCallback? onPressed;

  static const _size = 56.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final scheme = Theme.of(context).colorScheme;
    final destructiveButton = color == Colors.red;
    if (isChalkTheme(context)) {
      // チョーク: チョークで引いた丸の縁。通話終了（赤）だけ赤く塗る（2026-11-27）。通話画面の
      // 背景は黒の固定なので、線の色は、チョークの白。
      return Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Material(
            color: destructiveButton ? Colors.red.shade700 : Colors.transparent,
            shape: ChalkShapeBorder(
              borderRadius: BorderRadius.circular(_size / 2),
              color: scheme.onSurface,
              width: 2,
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Center(
                child: Icon(
                  icon,
                  color: destructiveButton ? Colors.white : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (isKinariTheme(context)) {
      // 生成り: 浮いた丸（明かり、細い線）。通話終了（赤）は、アイコンを赤くする（2026-11-27）。
      return Opacity(
        opacity: enabled ? 1 : 0.4,
        child: KinariRaisedCircle(
          color: scheme.surface,
          lineColor: scheme.onSurface,
          size: _size,
          onTap: onPressed,
          child: Icon(
            icon,
            color: destructiveButton ? Colors.red.shade700 : scheme.onSurface,
          ),
        ),
      );
    }
    if (isBlockTheme(context)) {
      // 版画は黒の太枠と硬い影の角丸の箱（2026-11-06）。通話終了（赤）だけ濃い赤の面に
      // 白いアイコン、他は淡い面に文字色のアイコン。アクセントは地色にも文字色にも使わない。
      final destructive = destructiveButton;
      final fill = destructive
          ? Colors.red.shade700
          : (Theme.of(context).brightness == Brightness.light
                ? Colors.white
                : scheme.surface);
      return Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          width: _size,
          height: _size,
          child: blockMaterialBox(
            context,
            color: fill,
            radius: 14,
            child: InkWell(
              onTap: onPressed,
              child: Center(
                child: Icon(
                  icon,
                  color: destructive ? Colors.white : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (isGlass) {
      // ガラスUIは背景を塗らず、`GlassIconButton`と同じ`GlassSurface`の
      // 円形パネル＋アイコン色そのもの（マイク等はグレー、通話終了は赤）で
      // 表現する（2026-08-30追加）。`GlassIconButton`はonPressedが非null
      // 必須で無効状態（暗く表示）を表現出来ないため流用せず、劇画分岐と
      // 同じ考え方で直接組み立てる。
      return Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          width: _size,
          height: _size,
          child: GlassSurface(
            variant: GlassVariant.card,
            opaque: true,
            borderRadius: BorderRadius.circular(_size / 2),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed,
                child: Center(
                  child: Icon(
                    icon,
                    color: GlassColors.adaptiveIconColor(
                      color,
                      Theme.of(context).brightness,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (isGekiga) {
      // 劇画スタイルは丸ではなく、他の劇画バッジと同じ手描き風の
      // モノクロボックス（GekigaBadgeShape）で表現する。`GekigaIconButton`
      // （既存の単体アイコンボタン）はonPressedが非null必須で無効状態を
      // 表現出来ないため流用せず、直接組み立てる。
      return Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              child: GekigaBadgeShape(
                color: color,
                seed: icon.hashCode,
                child: Icon(icon, color: GekigaColors.onPanel),
              ),
            ),
          ),
        ),
      );
    }
    // フラット: アクセントカラーの線で囲む（2026-11-27）。塗りは、意味の有る色のまま。
    return Material(
      color: enabled ? color : Colors.grey[300],
      shape: CircleBorder(side: BorderSide(color: scheme.primary, width: 1.5)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}
