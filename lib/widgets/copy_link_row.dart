import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gekiga/gekiga_icon_badge.dart';

/// 招待リンクの1行（リンク＋コピーボタン、2026-10-31追加）。リンクの文字を
/// クリックしても、コピーボタンを押しても、リンクをコピーし、コピーボタンが
/// 弾むように動いて、少しの間チェックの印に変わる。広場の招待・縁結びで共通。
class CopyLinkRow extends StatefulWidget {
  const CopyLinkRow({
    required this.link,
    this.gekiga = false,
    this.textStyle,
    this.wrapButton,
    super.key,
  });

  final String link;
  final bool gekiga;
  final TextStyle? textStyle;

  /// コピーボタンを包む（使い方ガイドの強調対象など）。
  final Widget Function(Widget button)? wrapButton;

  @override
  State<CopyLinkRow> createState() => _CopyLinkRowState();
}

class _CopyLinkRowState extends State<CopyLinkRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.45,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.45,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]).animate(_controller);
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.link));
    _controller.forward(from: 0);
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final icon = _copied ? Icons.check : Icons.copy_outlined;
    final Widget button = widget.gekiga
        ? GekigaIconButton(icon: icon, onPressed: _copy)
        : IconButton(icon: Icon(icon), onPressed: _copy);
    final animated = ScaleTransition(scale: _scale, child: button);
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            widget.link,
            maxLines: 1,
            style: widget.textStyle,
            onTap: _copy,
          ),
        ),
        widget.wrapButton?.call(animated) ?? animated,
      ],
    );
  }
}
