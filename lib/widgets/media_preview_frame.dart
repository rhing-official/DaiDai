import 'package:flutter/material.dart';

/// 画像・動画プレビューの外枠。フラットUI/劇画UI共通で使う（2026-08-12
/// 切り出し）。以前は`chat_screen.dart`（吹き出し内の添付画像/動画）と
/// `link_preview_card.dart`（リンクプレビューのサムネイル）がそれぞれ
/// 独自に角丸のロジックを実装しており、値がずれて「同じ画像なのに角丸な
/// 時と直角な時がある」不具合の原因になっていた。
Widget mediaPreviewFrame({required bool isGekiga, required Widget child}) {
  if (!isGekiga) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_contentRadius),
      child: child,
    );
  }
  return _GekigaPhotoMat(child: child);
}

const _contentRadius = 8.0;

/// 劇画UIで送信・受信した写真/動画メッセージを縁取る白いマット
/// （2026-08-10追加、2026-08-12改修: 角カットの面取りをやめて直角の
/// 矩形にし、外枠に黒枠を追加。内側の写真/動画自体もフラットUIと
/// 同じ角丸（[_contentRadius]）にした）。
class _GekigaPhotoMat extends StatelessWidget {
  const _GekigaPhotoMat({required this.child});

  final Widget child;

  static const _matWidth = 10.0;
  static const _borderWidth = 4.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border.fromBorderSide(
          BorderSide(color: Colors.black, width: _borderWidth),
        ),
      ),
      padding: const EdgeInsets.all(_matWidth),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_contentRadius),
        child: child,
      ),
    );
  }
}
