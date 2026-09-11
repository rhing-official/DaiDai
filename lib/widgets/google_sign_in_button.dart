import 'package:flutter/material.dart';

/// Googleの「Sign in with Google」ブランドガイドライン
/// （https://developers.google.com/identity/branding-guidelines）に準拠した
/// ログインボタン（2026-09-11追加）。DaiDaiの3 UIスタイル（フラット/ガラス/
/// 劇画）・アクセントカラーには追従させず、常にGoogle公式の固定配色にする
/// （ロゴの色・サイズを変更してはならないという公式規定に加え、テキスト色・
/// 背景・枠線も公式のライト/ダーク配色をそのまま使う）。画面のライト/ダーク
/// （[Brightness]）にはGoogle側が両方の公式配色を用意しているため追従する。
/// 形状はGoogleが提示する3種（Rectangular/Pill/Round）のうち、DaiDaiの他の
/// ボタンとも馴染むRectangular（角丸少なめ）を採用。
///
/// ロゴ画像は`assets/branding/google_g_logo.png`（公式配布アセットZipから
/// 抽出した「G」ロゴ単体、色・形状とも無加工）を使う。
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    required this.onPressed,
    this.loading = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final bool loading;

  static const _lightFill = Color(0xFFFFFFFF);
  static const _lightBorder = Color(0xFF747775);
  static const _lightText = Color(0xFF1F1F1F);
  static const _darkFill = Color(0xFF131314);
  static const _darkBorder = Color(0xFF8E918F);
  static const _darkText = Color(0xFFE3E3E3);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? _darkFill : _lightFill;
    final border = isDark ? _darkBorder : _lightBorder;
    final textColor = isDark ? _darkText : _lightText;

    return OutlinedButton(
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: fill,
        disabledBackgroundColor: fill,
        side: BorderSide(color: border, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.only(left: 12, right: 12),
        minimumSize: const Size(0, 40),
        splashFactory: NoSplash.splashFactory,
      ),
      child: loading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: textColor,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/branding/google_g_logo.png',
                  width: 18,
                  height: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  'Googleでログイン',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
    );
  }
}
