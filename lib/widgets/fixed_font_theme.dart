import 'package:flutter/material.dart';

import '../models/font_design.dart';

/// ユーザーが選んだフォントデザイン設定に関わらず、常にキウイ丸を適用する
/// ラッパー。ログイン・アカウント登録フローの画面専用（2026-09-16追加）。
/// フォント以外（色・UIスタイル）はTheme.of(context)をそのまま引き継ぐ。
class FixedFontTheme extends StatelessWidget {
  const FixedFontTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontFamily = FontDesign.kiwiMaru.fontFamily;
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: fontFamily),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: fontFamily),
      ),
      child: child,
    );
  }
}
