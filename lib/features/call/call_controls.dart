import 'package:flutter/material.dart';

/// 通話画面の丸いコントロールボタン（マイク・カメラ・切断など）。
/// 1対1通話（[CallScreen]）とグループ通話（[GroupCallScreen]）の両方で使う。
class CallRoundButton extends StatelessWidget {
  const CallRoundButton({
    required this.icon,
    required this.color,
    this.onPressed,
    super.key,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null,
      backgroundColor: onPressed == null ? Colors.grey[300] : color,
      onPressed: onPressed,
      child: Icon(icon, color: Colors.white),
    );
  }
}
