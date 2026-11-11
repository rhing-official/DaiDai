import 'package:flutter/material.dart';

import '../models/profile_card.dart';

/// 透過PNGのアイコンの透過部分に敷く色（2026-11-12）。アイコンの持ち主が選んだ色
/// （[ImageFocal.background]）で、未指定なら**透明**（後ろの面の色が透ける）。
/// 見る人の外観（ライト/ダーク）やアクセントカラーでは変えない（変えると、
/// 持ち主が決めたアイコンの見え方が人ごとに変わり、色が被って見えなくなる為）。
/// 呼び出し側（`ColoredBox`・`CircleAvatar`の`backgroundColor`）は、アイコンの
/// [focal]を渡す。
Color avatarBackdropColor(BuildContext context, ImageFocal? focal) {
  final background = focal?.background;
  return background == null ? Colors.transparent : Color(background);
}
