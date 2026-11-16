import 'package:flutter/widgets.dart';

import '../theme/motion.dart';

/// [Overlay]へ直接出すポップアップを、アプリの画面遷移（`buildDialogTransition`、設定の
/// 「画面遷移」の種類に従う）で出し入れする（2026-11-16）。Navigatorの無い通話画面
/// （PC・Webの`CallOverlay`）のBGMプレイヤー・画面共有メニューが、ダイアログと同じ動きで
/// 現れ、閉じる時も同じ動きで消えるようにする。
///
/// [builder]の`close`を呼ぶと、閉じる動きを再生してから取り除く（再生中の再呼び出しは無視）。
/// 戻り値の関数は、外から同じ閉じ方をする為のもの。
///
/// [transitionBuilder]を渡すと、出入りの動きをそれに置き換える（既定は`buildDialogTransition`、
/// 2026-11-17。通話のBGM・サウンドボードのシートが、画面遷移の設定に関係なく下からスライドする為）。
VoidCallback showTransitionedOverlay(
  OverlayState overlay, {
  required Widget Function(BuildContext context, VoidCallback close) builder,
  Widget Function(Animation<double> animation, Widget child)? transitionBuilder,
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
      transitionBuilder: transitionBuilder ?? buildDialogTransition,
    ),
  );
  overlay.insert(entry);
  return close;
}

class _TransitionedHost extends StatefulWidget {
  const _TransitionedHost({
    required this.builder,
    required this.onRemoved,
    required this.transitionBuilder,
    super.key,
  });

  final Widget Function(BuildContext context, VoidCallback close) builder;
  final Widget Function(Animation<double> animation, Widget child)
  transitionBuilder;
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
    return widget.transitionBuilder(
      _controller,
      widget.builder(context, close),
    );
  }
}
