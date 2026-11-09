import 'dart:async';

import 'package:flutter/material.dart';

/// 読み込みが一定時間（既定1秒）を超えた時だけ、中央にスピナーを出す部品。
///
/// 一瞬で終わる読み込みでは何も出さず（ちらつかない）、時間が掛かる時だけ
/// 「読み込み中」だと分かるようにする。画面（ページ・一覧・ポップアップ）の
/// 読み込み待ちの表示は、`SizedBox.shrink()`や即時の`CircularProgressIndicator`
/// ではなく、これを使う（2026-11-09、全ページで読み込みが遅い時のスピナーを統一）。
class DelayedSpinner extends StatefulWidget {
  const DelayedSpinner({super.key, this.delay = defaultDelay, this.size});

  /// 既定の待ち時間。
  static const defaultDelay = Duration(seconds: 1);

  final Duration delay;

  /// スピナーの大きさ（省略時はMaterialの既定）。
  final double? size;

  @override
  State<DelayedSpinner> createState() => _DelayedSpinnerState();
}

class _DelayedSpinnerState extends State<DelayedSpinner> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final spinner = widget.size == null
        ? const CircularProgressIndicator()
        : SizedBox(
            width: widget.size,
            height: widget.size,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
    return Center(child: spinner);
  }
}
