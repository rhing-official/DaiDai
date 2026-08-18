import 'package:flutter/material.dart';

import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/gekiga/gekiga_badge.dart';

/// 通話画面の丸いコントロールボタン（マイク・カメラ・切断など）。
/// 1対1通話（[CallScreen]）とグループ通話（[GroupCallScreen]）の両方で使う
/// （通話中のボタン列自体は[CallControlBar]が共通で組み立てる。これは
/// 個々のボタン1つ分の見た目のみを担当する）。フラット/劇画どちらの
/// スタイルにも対応する（2026-08-19、通話画面の独自UI化に伴い追加）。
class CallRoundButton extends StatelessWidget {
  const CallRoundButton({
    required this.icon,
    required this.color,
    required this.isGekiga,
    this.onPressed,
    super.key,
  });

  final IconData icon;
  final Color color;
  final bool isGekiga;
  final VoidCallback? onPressed;

  static const _size = 56.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
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
