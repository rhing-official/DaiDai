import 'package:flutter/material.dart';

import '../models/profile_card.dart';
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
    super.key,
  });

  final String? url;
  final ImageFocal? focal;
  final Widget fallback;
  final Color foregroundColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    final focal = this.focal;
    if (url != null && focal != null && !focal.isDefault) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.transparent,
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
      backgroundColor: Colors.transparent,
      foregroundColor: foregroundColor,
      child: url == null ? fallback : null,
    );
  }
}
