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
    this.trailing,
    this.copyOnlyByButton = false,
    super.key,
  });

  final String link;
  final bool gekiga;
  final TextStyle? textStyle;

  /// コピーボタンを包む（使い方ガイドの強調対象など）。
  final Widget Function(Widget button)? wrapButton;

  /// コピーボタンの右に並べる追加のボタン（設定のRhing Seed欄の「変更」、2026-11-07）。
  final Widget? trailing;

  /// trueなら、文字のタップ・選択では何もせず、コピーボタンだけでコピーする
  /// （設定のRhing Seed欄、2026-11-07）。
  final bool copyOnlyByButton;

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
          child: widget.copyOnlyByButton
              ? Text(
                  widget.link,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: widget.textStyle,
                )
              : SelectableText(
                  widget.link,
                  maxLines: 1,
                  style: widget.textStyle,
                  onTap: _copy,
                ),
        ),
        widget.wrapButton?.call(animated) ?? animated,
        ?widget.trailing,
      ],
    );
  }
}

/// コピーボタン単体（2026-11-06）。[CopyLinkRow]のボタンと同じ動き: 押すと弾むように動き、
/// 少しの間チェックの印に変わる。コピーする文字は押した時に[textBuilder]で求める
/// （入力欄の今の値）。空文字ならコピーしない。
class CopyIconButton extends StatefulWidget {
  const CopyIconButton({
    required this.textBuilder,
    this.gekiga = false,
    super.key,
  });

  final String Function() textBuilder;
  final bool gekiga;

  @override
  State<CopyIconButton> createState() => _CopyIconButtonState();
}

class _CopyIconButtonState extends State<CopyIconButton>
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
    final text = widget.textBuilder();
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
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
        : IconButton(icon: Icon(icon), tooltip: '', onPressed: _copy);
    return ScaleTransition(scale: _scale, child: button);
  }
}
