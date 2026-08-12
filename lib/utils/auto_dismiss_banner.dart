import 'dart:async';

import 'package:flutter/material.dart';

/// 現在画面に浮いている通知バナー（あれば1件のみ）。新しいバナーを表示する
/// 際・[dismissAutoDismissBanner]呼び出し時に即座に取り除く。
OverlayEntry? _activeEntry;

/// 現在表示中の通知バナーを閉じる。バナーの[showAutoDismissBanner]の
/// [actions]に独自ボタンを渡し、そのボタン自身でバナーを閉じたい場合に呼ぶ
/// （例: 「再送」ボタンが自分の処理を始める前にバナーを閉じる）。
void dismissAutoDismissBanner() {
  _activeEntry?.remove();
  _activeEntry = null;
}

/// 通知用途のSnackBarに代わり、画面上部に[duration]（既定3秒）だけ
/// コンテンツの上に浮かぶ形で表示して自動的に消えるバナーを表示する共通
/// ヘルパー（2026-08-12、`ScaffoldMessenger`の永続バナー領域を使う実装から
/// `Overlay`を使う実装へ変更。前者は画面のコンテンツを下に押しやってしまい
/// UXが低いという指摘を受けたため、レイアウトに影響しない浮遊カードにした）。
///
/// 呼び出し側がStateに`Timer?`フィールドを保持できる場合は[previousTimer]
/// に渡すと、短時間に連続して呼ばれた際に古いタイマーが新しいバナーを
/// 誤って消してしまうことを防げる。保持できないstateless widgetから呼ぶ
/// 場合は省略してよい（ごく稀に短時間で別の通知が連続すると、古いタイマーが
/// 新しいバナーをわずかに早く消してしまう可能性があるが、エラー表示という
/// 性質上実害は小さい）。
///
/// [actions]を省略すると、閉じるだけの最小限のアイコンボタン1つになる。
Timer showAutoDismissBanner(
  BuildContext context, {
  required String message,
  List<Widget>? actions,
  Timer? previousTimer,
  Duration duration = const Duration(seconds: 3),
}) {
  previousTimer?.cancel();
  dismissAutoDismissBanner();

  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  void dismiss() {
    entry.remove();
    if (identical(_activeEntry, entry)) _activeEntry = null;
  }

  entry = OverlayEntry(
    builder: (context) => _FloatingBanner(
      message: message,
      actions:
          actions ??
          [
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: dismiss,
            ),
          ],
    ),
  );
  _activeEntry = entry;
  overlay.insert(entry);
  return Timer(duration, dismiss);
}

class _FloatingBanner extends StatelessWidget {
  const _FloatingBanner({required this.message, required this.actions});

  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: colorScheme.surfaceContainerHigh,
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
