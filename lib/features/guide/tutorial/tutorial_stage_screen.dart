import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/tutorial_content.dart';
import 'tutorial_controller.dart';

/// 操作を促すガイドを実行する専用の全画面（2026-10-17追加）。ユーザーの今の画面の
/// 上に開き、[child]に**練習用の画面**（`PracticeHome`＝本物の画面＋偽のデータ）を
/// 置く。今の画面は下に残るため、作業の途中でも状態に左右されず、ガイドを終えると
/// 元の画面にそのまま戻れる。
///
/// ガイドの状態と連動して閉じる: やめる・Esc・戻る・完了カードの「閉じる」でガイドが
/// 終わったらこの画面も閉じる。逆に、ユーザーがこの画面を閉じたらガイドも中断する。
/// ガイドが実行されていないのに開かれた場合（URLの直接指定など）は、ホームへ戻す。
class TutorialStageScreen extends ConsumerStatefulWidget {
  const TutorialStageScreen({
    required this.child,
    this.startScript,
    this.onClosed,
    super.key,
  });

  final Widget child;

  /// 指定すると、この画面が開いた時にその台本を始める（初回ガイドのように、ルートで
  /// なく画面として使う場合）。nullなら、ガイドは呼び出し側が先に始めておく。
  final TutorialScript? startScript;

  /// 指定すると、閉じる時にルーターを操作せず、これを1回だけ呼ぶ。
  final VoidCallback? onClosed;

  @override
  ConsumerState<TutorialStageScreen> createState() =>
      _TutorialStageScreenState();
}

class _TutorialStageScreenState extends ConsumerState<TutorialStageScreen> {
  /// `dispose`でガイドを終えるために、先に保持しておく（`dispose`の中で祖先を引くと
  /// 不安定なため）。
  late final ProviderContainer _container;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final script = widget.startScript;
      if (script != null && ref.read(tutorialControllerProvider) == null) {
        ref.read(tutorialControllerProvider.notifier).start(script);
        return;
      }
      if (ref.read(tutorialControllerProvider) == null) {
        _close(toHome: true);
      }
    });
  }

  @override
  void dispose() {
    // この画面が閉じられたら（戻る操作など）ガイドも終える。
    final container = _container;
    Future.microtask(() {
      try {
        if (container.read(tutorialControllerProvider) != null) {
          container.read(tutorialControllerProvider.notifier).cancel();
        }
      } on StateError {
        // アプリ全体が破棄された後（テストの片付け等）は何もしない。
      }
    });
    super.dispose();
  }

  void _close({bool toHome = false}) {
    if (_closing || !mounted) return;
    _closing = true;
    // ノート・アルバムのボタンはメニュー（別のルート）を開くため、ガイドがその状態で
    // 終わると、下の戻る操作がステージではなくメニューを閉じてしまい、練習用の画面に
    // 取り残される。先に、ステージの上にある メニュー・ダイアログ等を閉じておく。
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route is! PopupRoute);
    final onClosed = widget.onClosed;
    if (onClosed != null) {
      onClosed();
      return;
    }
    final router = GoRouter.of(context);
    if (toHome || !router.canPop()) {
      router.go('/');
    } else {
      router.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TutorialState?>(tutorialControllerProvider, (previous, next) {
      if (previous != null && next == null) _close();
    });
    return Scaffold(body: SafeArea(child: widget.child));
  }
}
