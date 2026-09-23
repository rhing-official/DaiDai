import 'package:flutter/material.dart';

/// [GoogleSignInButton]（`google_sign_in_button.dart`、Googleの「Sign in with
/// Google」ブランドガイドライン準拠の配色ロジック）を、ログイン画面の他の
/// 主要ログイン手段（QRコードでログイン・パスキーでログイン）にも流用する
/// ための共通Widget（2026-09-23追加、ログイン画面のボタンデザイン統一）。
///
/// DaiDaiの3 UIスタイル（フラット/ガラス/劇画）・アクセントカラーには
/// 意図的に追従しない固定配色（ライト/ダークの[Brightness]のみに追従）。
/// CLAUDE.mdの「テキストは背景と反対色」ルールには合致するが、「アクセント
/// カラーはボタンの地色として使う」原則からは意図的に外れた例外。
class BrandedBlockButton extends StatelessWidget {
  const BrandedBlockButton({
    required this.onPressed,
    required this.label,
    required this.icon,
    this.loading = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final String label;
  final Widget icon;
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
                IconTheme.merge(
                  data: IconThemeData(color: textColor, size: 18),
                  child: icon,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
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
