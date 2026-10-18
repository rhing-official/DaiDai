import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../l10n/strings.dart';
import '../../../providers/app_locale_provider.dart';
import '../../../router/back_stack.dart';
import 'hand_drawn_circle.dart';
import 'tutorial_controller.dart';

/// 操作を促すガイドの案内の層（2026-10-17追加）。`main.dart`の`MaterialApp`の
/// `builder`で、全ルートより前面に重ねる。ガイドを実行していない間は何も描かず、
/// タップも吸収しない。
///
/// 実行中は、画面を暗くして今押してほしい場所だけを「穴」にし、その周りに手描きの
/// 丸を描き進め、説明の吹き出しを出す。**穴の外のタップは吸収し、穴の中のタップだけ
/// 下のボタンへ通す**（穴を囲む4枚の矩形でベールを作る）。押されたかどうかは
/// `TutorialTarget`が検知する。「やめる」・Esc・戻る操作でいつでも中断できる。
class TutorialOverlay extends ConsumerStatefulWidget {
  const TutorialOverlay({super.key});

  @override
  ConsumerState<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends ConsumerState<TutorialOverlay>
    with TickerProviderStateMixin {
  /// 穴の周りの余白。ボタンの枠（劇画UIのタイルの外枠など、目印の大きさより外に
  /// 描かれる部分）まで暗くならないよう、ボタンより広めに開ける（2026-10-17、
  /// 劇画UIで押すボタンが暗いままに見えるという指摘で6→12に拡大）。隣のボタンとの
  /// 間隔（約40px）より小さいため、隣のボタンまで通ることはない。
  static const _holePadding = 12.0;

  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Ticker _poll;
  final ValueNotifier<Rect?> _rect = ValueNotifier(null);

  /// 目印が見つからないまま3秒たったら、進まない時の案内を出す。時刻は実時間ではなく
  /// ティッカーの経過時間で数える（フレームに連動するため、テストでも進められる）。
  final ValueNotifier<bool> _showWaitingHint = ValueNotifier(false);
  Duration? _waitStart;
  bool _usingFallback = false;
  Duration _now = Duration.zero;

  @override
  void initState() {
    super.initState();
    _poll = createTicker(_onTick);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _poll.dispose();
    _draw.dispose();
    _rect.dispose();
    _showWaitingHint.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (ref.read(tutorialControllerProvider) == null) return false;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      ref.read(tutorialControllerProvider.notifier).cancel();
      return true;
    }
    return false;
  }

  /// 毎フレーム、今の手順の目印の位置を取り直す（画面遷移・スクロール中も追従）。
  void _onTick(Duration elapsed) {
    // 要素が外れた後にティッカーが最後に1回呼ばれることがある。
    if (!mounted) return;
    _now = elapsed;
    final step = ref.read(tutorialControllerProvider)?.step;
    if (step == null) {
      _rect.value = null;
      return;
    }
    final registry = ref.read(tutorialTargetRegistryProvider);
    // 次の目印が現れたら進む手順（入力欄に文字が入ると送信ボタンが現れる、等）。
    final until = step.advanceWhenVisible;
    if (until != null && registry.rectOf(until) != null) {
      ref
          .read(tutorialControllerProvider.notifier)
          .advance(fromIndex: ref.read(tutorialControllerProvider)?.index);
      return;
    }
    var rect = registry.rectOf(step.targetId);
    // 目印がまだ無い間、代わりに明るく抜いておく場所（送信ボタンは文字を入れるまで
    // 現れないため、その間も入力欄を使えるようにする）。丸は描かず、待機の案内も出さない。
    final fallbackId = step.fallbackTargetId;
    final fallback = rect == null && fallbackId != null
        ? registry.rectOf(fallbackId)
        : null;
    final wasFallback = _usingFallback;
    _usingFallback = fallback != null;
    if (fallback != null) rect = fallback;
    if (rect == null) {
      _waitStart ??= elapsed;
      if (!_showWaitingHint.value &&
          elapsed - _waitStart! >= const Duration(seconds: 3)) {
        _showWaitingHint.value = true;
      }
    } else {
      _waitStart = null;
      if (_showWaitingHint.value) _showWaitingHint.value = false;
    }
    if (rect == _rect.value) return;
    // 目印が見つかった瞬間（代わりの場所から本来の目印へ切り替わった瞬間も）から
    // 丸を描き始める。
    if (!_usingFallback &&
        (_rect.value == null || wasFallback) &&
        rect != null) {
      _draw.forward(from: 0);
    }
    _rect.value = rect;
  }

  void _resetForStep() {
    _rect.value = null;
    _usingFallback = false;
    _draw.reset();
    _waitStart = _now;
    _showWaitingHint.value = false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TutorialState?>(tutorialControllerProvider, (previous, next) {
      if (next == null) {
        _poll.stop();
        _rect.value = null;
        _draw.reset();
        _waitStart = null;
        _showWaitingHint.value = false;
      } else {
        if (previous == null || previous.index != next.index) _resetForStep();
        if (!_poll.isActive && !next.done) _poll.start();
        if (next.done) _poll.stop();
      }
    });
    final state = ref.watch(tutorialControllerProvider);
    if (state == null) return const SizedBox.shrink();
    if (!_poll.isActive && !state.done) {
      // 初回（listenは変化の時だけ呼ばれるため、開始直後はここで始める）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_poll.isActive) {
          _resetForStep();
          _poll.start();
        }
      });
    }
    final strings = ref.watch(appStringsProvider);
    final locale = ref.watch(appLocaleProvider);
    final step = state.step;

    return BackEntry(
      active: true,
      onBack: () => ref.read(tutorialControllerProvider.notifier).cancel(),
      child: Positioned.fill(
        child: Material(
          type: MaterialType.transparency,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screen = constraints.biggest;
              return ValueListenableBuilder<Rect?>(
                valueListenable: _rect,
                builder: (context, rect, _) {
                  // 自由に触る手順（freeform）は、暗くも止めもしないため穴を持たない。
                  final freeform = state.step?.freeform ?? false;
                  final hole = (rect == null || state.done || freeform)
                      ? null
                      : rect.inflate(_holePadding);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (!freeform || state.done) ...[
                        IgnorePointer(
                          child: CustomPaint(
                            painter: TutorialScrimPainter(hole: hole),
                          ),
                        ),
                        ..._barriers(
                          screen,
                          // 押さない手順（情報の手順）は、穴の上も含めて画面全体を吸収する。
                          // 出来事で進む手順（advanceOnEvent）は、穴の中を操作できる。
                          (step != null &&
                                  !step.requiresTap &&
                                  step.advanceOnEvent == null)
                              ? null
                              : hole,
                        ),
                      ],
                      if (hole != null &&
                          step != null &&
                          step.showCircle &&
                          !_usingFallback)
                        IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _draw,
                            builder: (context, _) => CustomPaint(
                              painter: HandDrawnCirclePainter(
                                rect: rect!,
                                progress: Curves.easeInOut.transform(
                                  _draw.value,
                                ),
                                seed: step.targetId.hashCode,
                              ),
                            ),
                          ),
                        ),
                      if (state.done)
                        _DoneCard(
                          title: strings.tutorialDoneTitle,
                          message: state.script.doneMessage.of(locale),
                          closeLabel: strings.tutorialDoneClose,
                          onClose: () => ref
                              .read(tutorialControllerProvider.notifier)
                              .cancel(),
                        )
                      else if (step != null)
                        ValueListenableBuilder<bool>(
                          valueListenable: _showWaitingHint,
                          builder: (context, showHint, _) =>
                              // 目印がまだ見つからない間（練習用の画面が現れる途中など）は
                              // 吹き出しを出さない。画面の隅に仮の位置で一瞬出るのを防ぐ。
                              // 3秒たっても見つからない時だけ、待機の案内つきで出す。
                              (hole == null && !showHint && !freeform)
                              ? const SizedBox.shrink()
                              : _Caption(
                                  screen: screen,
                                  hole: hole,
                                  freeform: freeform,
                                  atTop: step.captionAtTop,
                                  text: step.caption.of(locale),
                                  counter: strings.tutorialStepCounterTemplate(
                                    state.index + 1,
                                    state.script.steps.length,
                                  ),
                                  // 押さない手順は「次へ」で進める。
                                  nextLabel:
                                      (step.requiresTap &&
                                          step.advanceOnEvent == null &&
                                          !freeform)
                                      ? null
                                      : strings.tutorialNext,
                                  onNext:
                                      (step.requiresTap &&
                                          step.advanceOnEvent == null &&
                                          !freeform)
                                      ? null
                                      : () => ref
                                            .read(
                                              tutorialControllerProvider
                                                  .notifier,
                                            )
                                            .advance(fromIndex: state.index),
                                ),
                        ),
                      // 常に押せる「やめる」（強制は穴の外の操作を止めることに限る）。
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 8,
                        right: 12,
                        child: PointerInterceptor(
                          child: FilledButton.tonal(
                            onPressed: () => ref
                                .read(tutorialControllerProvider.notifier)
                                .cancel(),
                            child: Text(strings.tutorialStop),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// 穴の外のタップを吸収する矩形。穴が無い（目印待ち・完了）間は画面全体。
  List<Widget> _barriers(Size screen, Rect? hole) {
    Widget block(Rect r) => Positioned.fromRect(
      rect: r,
      child: PointerInterceptor(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          onPanDown: (_) {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    final full = Offset.zero & screen;
    if (hole == null) return [block(full)];
    final h = hole.intersect(full);
    return [
      block(Rect.fromLTRB(0, 0, screen.width, h.top)),
      block(Rect.fromLTRB(0, h.bottom, screen.width, screen.height)),
      block(Rect.fromLTRB(0, h.top, h.left, h.bottom)),
      block(Rect.fromLTRB(h.right, h.top, screen.width, h.bottom)),
    ];
  }
}

/// 画面を暗くし、[hole]だけを角丸でくり抜く（2026-10-17）。穴は`Path.combine`では
/// なく、レイヤーに暗い塗りを敷いて穴を`BlendMode.clear`で抜く方法で作る
/// （描画環境によらず確実に抜ける。`Path.combine`では穴が抜けず、押すボタンが
/// 暗いままに見える不具合があった）。
class TutorialScrimPainter extends CustomPainter {
  const TutorialScrimPainter({required this.hole});

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(
      bounds,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );
    final hole = this.hole;
    if (hole != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole, const Radius.circular(16)),
        Paint()..blendMode = BlendMode.clear,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TutorialScrimPainter oldDelegate) =>
      oldDelegate.hole != hole;
}

/// 手順の説明の吹き出し。穴があればその上下（広い側）に、無ければ画面の下に出す。
class _Caption extends StatelessWidget {
  const _Caption({
    required this.screen,
    required this.hole,
    required this.text,
    required this.counter,
    this.freeform = false,
    this.atTop = false,
    this.nextLabel,
    this.onNext,
  });

  final Size screen;
  final Rect? hole;
  final String text;
  final String counter;

  /// 自由に触る手順のカード。目印には寄せず、画面の下（[atTop]なら上）に固定し、
  /// 下に置くときはキーボードの上に持ち上げる。
  final bool freeform;
  final bool atTop;

  /// 押さない手順（情報の手順）の「次へ」ボタン。押させる手順では出さない。
  final String? nextLabel;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = (screen.width - 32).clamp(0.0, 340.0);
    final card = PointerInterceptor(
      child: Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              counter,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (onNext != null && nextLabel != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  key: const ValueKey('tutorial-next'),
                  onPressed: onNext,
                  child: Text(nextLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (freeform) {
      final insets = MediaQuery.of(context);
      return atTop
          ? Positioned(
              left: 0,
              right: 0,
              top: insets.padding.top + 56,
              child: Center(child: card),
            )
          : Positioned(
              left: 0,
              right: 0,
              bottom: insets.viewInsets.bottom + 16,
              child: Center(child: card),
            );
    }
    final hole = this.hole;
    if (hole == null) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 32,
        child: Center(child: card),
      );
    }
    final left = (hole.center.dx - width / 2).clamp(
      16.0,
      (screen.width - 16 - width).clamp(16.0, double.infinity),
    );
    if (hole.center.dy < screen.height / 2) {
      return Positioned(left: left, top: hole.bottom + 28, child: card);
    }
    return Positioned(
      left: left,
      bottom: screen.height - hole.top + 28,
      child: card,
    );
  }
}

/// 全ての手順を終えた時の完了カード。
class _DoneCard extends StatelessWidget {
  const _DoneCard({
    required this.title,
    required this.message,
    required this.closeLabel,
    required this.onClose,
  });

  final String title;
  final String message;
  final String closeLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: PointerInterceptor(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onClose, child: Text(closeLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
