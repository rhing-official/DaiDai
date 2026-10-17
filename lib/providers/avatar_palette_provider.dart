import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/generated_avatar.dart';

/// 画像の無い住人のアイコン（頭文字の丸）の色の候補（2026-10-17追加）。通常は
/// [GeneratedAvatar.palette]だが、使い方ガイドの練習用の画面では青緑を除いた
/// 候補に差し替える（`PracticeHome`参照）。
final avatarPaletteProvider = Provider<List<Color>>(
  (ref) => GeneratedAvatar.palette,
);
