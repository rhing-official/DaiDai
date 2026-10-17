import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/pane_visibility.dart';
import 'tutorial_controller.dart';

/// ガイドで「ここを押して」と案内する場所の目印（2026-10-17追加）。[child]を
/// `GlobalKey`で登録して画面上の位置を案内の層（`TutorialOverlay`）へ伝え、
/// 今の手順の目印が押されたら次の手順へ進める。[child]自身のタップ処理は
/// 妨げない（`Listener`で観測するだけ）。
///
/// UIスタイル（フラット／ガラス／劇画）や画面幅で中身のウィジェットが変わる
/// 場所では、その分岐の**外側**に巻く。ガイドを実行していない間は何もしない。
class TutorialTarget extends ConsumerStatefulWidget {
  const TutorialTarget({required this.id, required this.child, super.key});

  final String id;
  final Widget child;

  @override
  ConsumerState<TutorialTarget> createState() => _TutorialTargetState();
}

class _TutorialTargetState extends ConsumerState<TutorialTarget> {
  final _key = GlobalKey();
  late final TutorialTargetRegistry _registry = ref.read(
    tutorialTargetRegistryProvider,
  );

  /// 押した結果この目印自身が画面から消える場合（相手を選ぶと会話が開く、送信で
  /// 入力欄が空になりボタンが消える等）でも、`onPointerUp`はその後に届くことがある。
  /// そのとき`ref`は使えないため、先に取っておく。
  late final TutorialController _controller = ref.read(
    tutorialControllerProvider.notifier,
  );

  bool _registered = false;

  /// このウィジェットが今、実際に画面に見えているか。`IndexedStack`で保持される
  /// 非選択のタブや、別ルートの下に隠れた画面の目印を除くため（通話の
  /// 埋め込み表示と同じ判定）。
  bool _visible(BuildContext context) =>
      TickerMode.valuesOf(context).enabled && PaneVisibility.of(context);

  @override
  void initState() {
    super.initState();
    // 破棄後に`ref`を触らないよう、ここで取り込んでおく。
    _controller;
  }

  @override
  void dispose() {
    if (_registered) _registry.unregister(widget.id, _key);
    super.dispose();
  }

  void _onPointerUp(PointerUpEvent event) {
    final state = _controller.current;
    final step = state?.step;
    // 押さない手順（情報の手順）では、目印が押されても進めない（「次へ」で進める）。
    if (step == null || !step.requiresTap || step.targetId != widget.id) return;
    final box = _key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    if (!(Offset.zero & box.size).contains(box.globalToLocal(event.position))) {
      return;
    }
    // ボタン自身の処理（画面遷移・コピーなど）が先に実行されてから進める。
    final index = state!.index;
    // 押した結果この目印自身が画面から消える場合（相手を選ぶと会話が開く等）でも
    // 進められるよう、先にコントローラーを取っておき、`mounted`には依存しない。
    Timer(const Duration(milliseconds: 150), () {
      _controller.advance(fromIndex: index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible(context);
    if (_registered) {
      _registry.update(widget.id, _key, visible: visible);
    } else {
      _registry.register(widget.id, _key, visible: visible);
      _registered = true;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: _onPointerUp,
      child: KeyedSubtree(key: _key, child: widget.child),
    );
  }
}
