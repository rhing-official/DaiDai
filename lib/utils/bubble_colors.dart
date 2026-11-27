import 'dart:ui';

/// メッセージの吹き出しの塗り色（2026-11-27）。
///
/// 背景（[background]）から、はっきり離れた色にする。ライトの背景なら濃く、ダークの背景なら
/// 明るくする。固定の灰色にしていた時は、背景とほとんど同じ色になる組み合わせが有り、
/// 吹き出しが見えにくかった。
/// 自分の吹き出し（[isMe]）は、相手の色にアクセントカラー（[accent]）を混ぜる。文字色は、
/// 呼び出し側が、塗りの明るさから決める。アクセントカラーそのままで塗らないのは、明暗
/// 次第で文字が読めなくなるため。
///
/// [strength]は、背景からの離し具合の倍率。へこんだ面で描く生成りは、小さくする。
Color chatBubbleFill({
  required Color background,
  required Color accent,
  required bool isMe,
  double strength = 1.0,
}) {
  final dark = background.computeLuminance() < 0.5;
  // ダークは、明るい側へ離す方が見えやすい。真っ黒の背景でも、塗りが沈まない大きさにする。
  final step = (dark ? 0.16 : 0.12) * strength;
  final other = Color.lerp(
    background,
    dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
    step,
  )!;
  if (!isMe) return other;
  // 半透明のアクセントカラーは、相手の色の上に重ねた見た目にしてから混ぜる。
  final accentOpaque = Color.alphaBlend(accent, other);
  return Color.lerp(other, accentOpaque, 0.25)!;
}
