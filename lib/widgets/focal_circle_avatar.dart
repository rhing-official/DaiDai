import 'package:flutter/material.dart';

import '../models/profile_card.dart';
import '../theme/block/block_theme.dart';
import '../utils/avatar_backdrop.dart';
import 'focal_image.dart';

/// 一覧・メッセージ画面等の円形アイコン（`CircleAvatar`相当）。工房で編集した
/// アイコンの表示領域（[focal]）を反映する（2026-10-11追加）。焦点が未設定・
/// 既定（中央・等倍）の場合は従来の`CircleAvatar(backgroundImage:)`と同じ
/// 見た目。画像が無い場合は[fallback]を表示する。
class FocalCircleAvatar extends StatelessWidget {
  const FocalCircleAvatar({
    required this.url,
    required this.fallback,
    required this.foregroundColor,
    this.focal,
    this.radius = 20,
    this.blockFrame = false,
    super.key,
  });

  final String? url;
  final ImageFocal? focal;
  final Widget fallback;
  final Color foregroundColor;
  final double radius;

  /// trueで、版画のテーマの時だけ丸ではなく角丸の四角に黒の太枠と硬い影で描く
  /// （語らい一覧など、呼び出し側が版画に揃えたい所だけ指定する）。
  final bool blockFrame;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    final focal = this.focal;
    final backdrop = url != null
        ? avatarBackdropColor(context)
        : Colors.transparent;
    if (blockFrame && isBlockTheme(context)) {
      final theme = Theme.of(context);
      final size = radius * 2;
      final inner = BorderRadius.circular(
        BlockTheme.radius - BlockTheme.borderWidth,
      );
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(BlockTheme.radius),
          border: Border.all(
            color: BlockTheme.lineColor(theme.brightness),
            width: BlockTheme.borderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.primary
                  : BlockTheme.lightLine,
              offset: const Offset(2, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: inner,
          child: ColoredBox(
            color: backdrop,
            child: url != null
                ? (focal != null && !focal.isDefault
                      ? FocalImage(url: url, focal: focal)
                      : Image.network(url, fit: BoxFit.cover))
                : Center(
                    child: IconTheme(
                      data: IconThemeData(color: foregroundColor),
                      child: fallback,
                    ),
                  ),
          ),
        ),
      );
    }
    if (url != null && focal != null && !focal.isDefault) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backdrop,
        child: ClipOval(
          child: SizedBox(
            width: radius * 2,
            height: radius * 2,
            child: FocalImage(url: url, focal: focal),
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage: url != null ? NetworkImage(url) : null,
      backgroundColor: backdrop,
      foregroundColor: foregroundColor,
      child: url == null ? fallback : null,
    );
  }
}
