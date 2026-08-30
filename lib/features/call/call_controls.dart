import 'package:flutter/material.dart';

import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/glass/glass_colors.dart';
import '../../widgets/gekiga/gekiga_badge.dart';
import '../../widgets/glass/glass_surface.dart';

/// 通話画面の丸いコントロールボタン（マイク・カメラ・切断など）。
/// 1対1通話（[CallScreen]）とグループ通話（[GroupCallScreen]）の両方で使う
/// （通話中のボタン列自体は[CallControlBar]が共通で組み立てる。これは
/// 個々のボタン1つ分の見た目のみを担当する）。フラット/劇画/ガラスいずれの
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
    if (isGlass) {
      // ガラスUIは背景を塗らず、`GlassIconButton`と同じ`GlassSurface`の
      // 円形パネル＋アイコン色そのもの（マイク等はグレー、通話終了は赤）で
      // 表現する（2026-08-30追加）。`GlassIconButton`はonPressedが非null
      // 必須で無効状態（暗く表示）を表現できないため流用せず、劇画分岐と
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
      // 表現できないため流用せず、直接組み立てる。
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
    return Material(
      color: enabled ? color : Colors.grey[300],
      shape: const CircleBorder(),
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
