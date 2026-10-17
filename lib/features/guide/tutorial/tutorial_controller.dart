import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/tutorial_content.dart';

/// 実行中のガイドの状態（2026-10-17追加）。[index]は今の手順、全て押し終えると
/// [done]が`true`になり完了メッセージを出す。
class TutorialState {
  const TutorialState({
    required this.script,
    this.index = 0,
    this.done = false,
  });

  final TutorialScript script;
  final int index;
  final bool done;

  /// 今押してほしい手順。完了後は`null`。
  TutorialStep? get step => done ? null : script.steps[index];
}

/// ガイドの開始・進行・中断。実行中でなければ状態は`null`。
class TutorialController extends Notifier<TutorialState?> {
  @override
  TutorialState? build() => null;

  void start(TutorialScript script) {
    state = TutorialState(script: script);
  }

  /// 今の手順を押し終えた。[fromIndex]が今の手順と違う場合（遅れて届いた通知）は無視。
  void advance({int? fromIndex}) {
    final current = state;
    if (current == null || current.done) return;
    if (fromIndex != null && fromIndex != current.index) return;
    if (current.index + 1 >= current.script.steps.length) {
      state = TutorialState(
        script: current.script,
        index: current.index,
        done: true,
      );
    } else {
      state = TutorialState(script: current.script, index: current.index + 1);
    }
  }

  /// やめる／完了後に閉じる。
  void cancel() {
    state = null;
  }
}

final tutorialControllerProvider =
    NotifierProvider<TutorialController, TutorialState?>(
      TutorialController.new,
    );

/// 画面上の「押す場所」の登録簿。同じidを広い画面・狭い画面・非表示のタブなど
/// 複数の場所が持ちうるため、idごとに複数のキーと「今見えているか」を持つ。
class TutorialTargetRegistry {
  final Map<String, Map<GlobalKey, bool>> _targets = {};

  void register(String id, GlobalKey key, {required bool visible}) {
    _targets.putIfAbsent(id, () => {})[key] = visible;
  }

  void update(String id, GlobalKey key, {required bool visible}) {
    final entries = _targets[id];
    if (entries != null && entries.containsKey(key)) entries[key] = visible;
  }

  void unregister(String id, GlobalKey key) {
    final entries = _targets[id];
    if (entries == null) return;
    entries.remove(key);
    if (entries.isEmpty) _targets.remove(id);
  }

  /// [id]の目印のうち、今見えているものの画面上の位置。見つからなければ`null`。
  /// 同じidが複数ある場合は、**最後に登録されたもの（最前面にあるはずのもの）**を
  /// 優先する。
  Rect? rectOf(String id) {
    final entries = _targets[id];
    if (entries == null) return null;
    for (final entry in entries.entries.toList().reversed) {
      if (!entry.value) continue;
      final box = entry.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.isEmpty) continue;
      return rect;
    }
    return null;
  }
}

final tutorialTargetRegistryProvider = Provider<TutorialTargetRegistry>(
  (ref) => TutorialTargetRegistry(),
);
