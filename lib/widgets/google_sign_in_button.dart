import 'package:flutter/material.dart';

import 'branded_block_button.dart';

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
///
/// 配色ロジック本体は[BrandedBlockButton]に集約されており（2026-09-23、
/// QRコード・パスキーログインボタンにも同じ見た目を流用するため）、この
/// クラスはGoogleロゴ・文言を渡す薄いラッパー。
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    required this.onPressed,
    this.loading = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return BrandedBlockButton(
      onPressed: onPressed,
      loading: loading,
      icon: Image.asset(
        'assets/branding/google_g_logo.png',
        width: 18,
        height: 18,
      ),
      label: 'Googleでログイン',
    );
  }
}
