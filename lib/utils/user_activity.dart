import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// 画面を操作していたかの記録（2026-11-26）。通話が終わった時に、相手の語らいへ飛んでよいかの
/// 判定に使う（操作の途中で画面が切り替わらないようにする為）。
///
/// タッチ・クリック・キー入力の時刻を、直近だけ覚える。
class UserActivity {
  UserActivity._();

  static final UserActivity instance = UserActivity._();

  final List<int> _touchTimes = [];
  bool _attached = false;

  /// 記録を始める。何度呼んでも1回だけ。
  void attach() {
    if (_attached) return;
    _attached = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      _record(DateTime.now().millisecondsSinceEpoch);
    }
  }

  void _record(int ms) {
    _touchTimes.add(ms);
    if (_touchTimes.length > 64) _touchTimes.removeRange(0, 32);
  }

  /// 自分の終話ボタンの操作は、数えない。終話の直前の[window]に有った操作を捨てる。
  void forgetRecent({Duration window = const Duration(milliseconds: 1500)}) {
    final limit = DateTime.now().millisecondsSinceEpoch - window.inMilliseconds;
    _touchTimes.removeWhere((t) => t >= limit);
  }

  /// 直近[within]の間に操作が有ったか。
  bool touchedWithin(Duration within) {
    if (_touchTimes.isEmpty) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - _touchTimes.last <= within.inMilliseconds;
  }

  @visibleForTesting
  void debugReset() => _touchTimes.clear();

  @visibleForTesting
  void debugRecord(int ms) => _record(ms);
}

/// 入力欄に、まだ送っていない文字が有る間だけ数える（2026-11-26）。通話が終わった時に、
/// 入力の途中で画面が切り替わらないようにする為。
class ComposerDraftTracker {
  ComposerDraftTracker._();

  static final Set<Object> _owners = <Object>{};

  static void set(Object owner, bool hasText) {
    if (hasText) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
  }

  static bool get hasDraft => _owners.isNotEmpty;
}
