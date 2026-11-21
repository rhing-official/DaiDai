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
}) => showTransitionedOverlayHandle(
  overlay,
  builder: builder,
  transitionBuilder: transitionBuilder,
).close;

/// [showTransitionedOverlay]の、閉じ方を2通り持つ版（2026-11-21）。[close]は閉じる動きを
/// 再生してから取り除き、[removeNow]は動きなしで直ちに取り除く（ウィジェットの`dispose`の
/// ように、動きを待てない場面用）。長押し・「＋」・ぺったん・送信のポップアップが使う。
class TransitionedOverlayHandle {
  TransitionedOverlayHandle._(this._entry, this._key);

  final OverlayEntry _entry;
  final GlobalKey<_TransitionedHostState> _key;
  bool _removed = false;

  /// 取り除く。二重に呼ばれても、一度だけ取り除く（閉じる動きの途中で[removeNow]された後に、
  /// 動きの終了通知が来る場合がある）。
  void _remove() {
    if (_removed) return;
    _removed = true;
    _entry.remove();
  }

  /// 閉じる動きを再生してから取り除く（再生中の再呼び出しは無視）。
  void close() => _key.currentState?.close();

  /// 動きなしで、直ちに取り除く。
  void removeNow() => _remove();

  /// 中身（[showTransitionedOverlayHandle]の`builder`）を作り直す。
  void markNeedsBuild() {
    if (!_removed) _entry.markNeedsBuild();
  }
}

TransitionedOverlayHandle showTransitionedOverlayHandle(
  OverlayState overlay, {
  required Widget Function(BuildContext context, VoidCallback close) builder,
  Widget Function(Animation<double> animation, Widget child)? transitionBuilder,
}) {
  late final TransitionedOverlayHandle handle;
  final key = GlobalKey<_TransitionedHostState>();
  final entry = OverlayEntry(
    builder: (context) => _TransitionedHost(
      key: key,
      onRemoved: () => handle._remove(),
      builder: builder,
      transitionBuilder: transitionBuilder ?? buildDialogTransition,
    ),
  );
  handle = TransitionedOverlayHandle._(entry, key);
  overlay.insert(entry);
  return handle;
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
