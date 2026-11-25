import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/locked_call_providers.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart' show globalBackStack, globalRouter;
import '../../utils/user_activity.dart';
import 'active_call_session.dart';
import 'webrtc_call_controller.dart';
import 'webrtc_group_call_controller.dart';

/// 直近この時間に画面を操作していたら、通話が終わっても語らいへ飛ばない。
const kCallEndJumpIdleWindow = Duration(seconds: 3);

/// 通話が終わったら、その通話をした一対・広場の、通話を始めた寄合へ飛ぶ（2026-11-26）。
///
/// 通話の記録はサーバーが、通話を始めた寄合へ書く。通話に出ていた人は、その記録を未読にしない
/// （`incrementUnreadCounts`）ので、飛んだ先で、記録をそのまま見られる。
///
/// 次の時は飛ばない。操作の途中で、画面が切り替わらないようにする為。
/// - つながらなかった通話（出ていない）
/// - アプリが背景に有る、または端末がロックされている
/// - 通話をミニ表示にして、他の画面を使っていた
/// - 終わる直前の3秒以内に、画面を操作していた。自分の終話ボタンは、操作に数えない
/// - 入力欄に、送っていない文字が有る
class CallEndJump extends ConsumerStatefulWidget {
  const CallEndJump({super.key});

  @override
  ConsumerState<CallEndJump> createState() => _CallEndJumpState();
}

class _CallEndJumpState extends ConsumerState<CallEndJump> {
  ActiveCallSession? _tracked;
  bool _connected = false;
  Listenable? _listenable;

  @override
  void initState() {
    super.initState();
    UserActivity.instance.attach();
  }

  @override
  void dispose() {
    _listenable?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final s = _tracked;
    if (s == null) return;
    final connected = switch (s) {
      OneToOneCallSession(:final controller) =>
        controller.state == CallConnectionState.active,
      GroupCallSession(:final controller) =>
        controller.state == GroupCallConnectionState.active,
    };
    if (connected) _connected = true;
  }

  void _onSession(ActiveCallSession? previous, ActiveCallSession? next) {
    if (next != null) {
      if (!isSameCallSession(previous, next)) {
        _listenable?.removeListener(_onControllerChanged);
        _connected = false;
        _listenable = next.controllerListenable
          ..addListener(_onControllerChanged);
        _tracked = next;
        _onControllerChanged();
      } else {
        _tracked = next; // ミニ表示の切り替え
      }
      return;
    }
    final ended = _tracked;
    final connected = _connected;
    _tracked = null;
    _connected = false;
    _listenable?.removeListener(_onControllerChanged);
    _listenable = null;
    if (ended == null || !connected) return;
    if (!_mayJump(ended)) return;
    // 通話画面が閉じ終わってから飛ぶ。
    Timer(const Duration(milliseconds: 700), () => unawaited(_jump(ended)));
  }

  bool _mayJump(ActiveCallSession ended) {
    if (ended.minimized) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    if (ref.read(lockedCallModeProvider)) return false;
    if (UserActivity.instance.touchedWithin(kCallEndJumpIdleWindow)) {
      return false;
    }
    if (ComposerDraftTracker.hasDraft) return false;
    return true;
  }

  Future<void> _jump(ActiveCallSession ended) async {
    String? roomId;
    final String path;
    switch (ended) {
      case OneToOneCallSession(:final call):
        roomId = call.roomId;
        path = '/chat/dm/${call.dmId}';
      case GroupCallSession(:final groupCallId, :final groupId):
        path = '/chat/group/$groupId';
        try {
          final call = await ref
              .read(groupCallRepositoryProvider)
              .getGroupCall(groupCallId);
          roomId = call?.roomId;
        } catch (_) {
          // 取得できなければ、寄合の指定なしで開く。
        }
    }
    // 待つ間に、操作が始まっていたら飛ばない。
    if (!mounted ||
        UserActivity.instance.touchedWithin(const Duration(seconds: 1))) {
      return;
    }
    globalBackStack?.bypassGuardsBriefly();
    globalRouter?.go(
      roomId != null && roomId.isNotEmpty ? '$path?roomId=$roomId' : path,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ActiveCallSession?>(activeCallSessionProvider, _onSession);
    return const SizedBox.shrink();
  }
}
