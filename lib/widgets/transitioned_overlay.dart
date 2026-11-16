import 'package:flutter/widgets.dart';

import '../theme/motion.dart';

/// [Overlay]へ直接出すポップアップを、アプリの画面遷移（`buildDialogTransition`、設定の
/// 「画面遷移」の種類に従う）で出し入れする（2026-11-16）。Navigatorの無い通話画面
/// （PC・Webの`CallOverlay`）のBGMプレイヤー・画面共有メニューが、ダイアログと同じ動きで
/// 現れ、閉じる時も同じ動きで消えるようにする。
///
/// [builder]の`close`を呼ぶと、閉じる動きを再生してから取り除く（再生中の再呼び出しは無視）。
/// 戻り値の関数は、外から同じ閉じ方をする為のもの。
VoidCallback showTransitionedOverlay(
  OverlayState overlay, {
  required Widget Function(BuildContext context, VoidCallback close) builder,
}) {
  late final OverlayEntry entry;
  final key = GlobalKey<_TransitionedHostState>();
  void close() => key.currentState?.close();
  entry = OverlayEntry(
    builder: (context) => _TransitionedHost(
      key: key,
      onRemoved: () {
        if (entry.mounted) entry.remove();
      },
      builder: builder,
    ),
  );
  overlay.insert(entry);
  return close;
}

class _TransitionedHost extends StatefulWidget {
  const _TransitionedHost({
    required this.builder,
    required this.onRemoved,
    super.key,
  });

  final Widget Function(BuildContext context, VoidCallback close) builder;
  final VoidCallback onRemoved;

  @override
  State<_TransitionedHost> createState() => _TransitionedHostState();
}

class _TransitionedHostState extends State<_TransitionedHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: popSlideDuration,
    reverseDuration: popSlideDuration,
  );
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  void close() {
    if (_closing) return;
    _closing = true;
    _controller.reverse().whenCompleteOrCancel(widget.onRemoved);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return buildDialogTransition(_controller, widget.builder(context, close));
  }
}
