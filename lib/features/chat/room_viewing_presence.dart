import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/repository_providers.dart';
import '../../push_notifications.dart' show dismissRoomNotificationsLocal;
import '../../utils/room_notification_dismiss/room_notification_dismiss.dart';

/// いま前面で開いている寄合（2026-11-14）。通知を出さないための、端末側の判定に使う。
({String conversationId, String roomId})? _currentViewingRoom;

/// [conversationId]・[roomId]が、いま前面で開いている寄合か。
bool isViewingRoomNow(String? conversationId, String? roomId) {
  final current = _currentViewingRoom;
  return current != null &&
      current.conversationId == conversationId &&
      current.roomId == roomId;
}

/// この寄合のメッセージ画面を開いている間（アプリが前面）だけ、「いま見ている」ことを
/// `conversationPrefs`の`viewing`へ書く（2026-11-13）。サーバー（Cloud Functions）は、
/// その寄合を開いている人へはメッセージの通知を送らない。約30秒ごとに更新し、閉じる・
/// 寄合を切り替える・アプリを離れる時に消す（更新が90秒止まれば、サーバーが開いていない
/// 扱いにする）。
class RoomViewingPresence extends ConsumerStatefulWidget {
  const RoomViewingPresence({
    required this.userId,
    required this.conversationId,
    required this.roomId,
    required this.child,
    super.key,
  });

  final String userId;
  final String conversationId;
  final String roomId;
  final Widget child;

  @override
  ConsumerState<RoomViewingPresence> createState() =>
      _RoomViewingPresenceState();
}

class _RoomViewingPresenceState extends ConsumerState<RoomViewingPresence>
    with WidgetsBindingObserver {
  static const _heartbeat = Duration(seconds: 30);
  Timer? _timer;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.inactive &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.hidden) {
      _start();
    }
  }

  @override
  void didUpdateWidget(RoomViewingPresence old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId ||
        old.conversationId != widget.conversationId ||
        old.roomId != widget.roomId) {
      if (_active) {
        _clear(old.userId, old.conversationId);
        _start();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _stop();
    }
  }

  void _start() {
    _timer?.cancel();
    _active = true;
    _currentViewingRoom = (
      conversationId: widget.conversationId,
      roomId: widget.roomId,
    );
    // 自分で開いたら、その寄合の通知は消す（タップしなくてよい）。
    unawaited(
      dismissRoomNotificationsLocal(widget.conversationId, widget.roomId),
    );
    dismissWebRoomNotifications(widget.conversationId, widget.roomId);
    _write();
    _timer = Timer.periodic(_heartbeat, (_) => _write());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (!_active) return;
    _active = false;
    _releaseCurrent();
    _clear(widget.userId, widget.conversationId);
  }

  /// 自分が登録した寄合のときだけ解除する（寄合の切り替えで、新しい側の登録を消さない）。
  void _releaseCurrent() {
    if (isViewingRoomNow(widget.conversationId, widget.roomId)) {
      _currentViewingRoom = null;
    }
  }

  void _write() {
    unawaited(
      ref
          .read(conversationPrefsRepositoryProvider)
          .setViewing(
            userId: widget.userId,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
          )
          .catchError((_) {}),
    );
  }

  void _clear(String userId, String conversationId) {
    unawaited(
      ref
          .read(conversationPrefsRepositoryProvider)
          .clearViewing(userId: userId, conversationId: conversationId)
          .catchError((_) {}),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // dispose中は`ref`を使えないことがあるため、先に保持しておく。
    _timer?.cancel();
    if (_active) {
      _releaseCurrent();
      try {
        _clear(widget.userId, widget.conversationId);
      } catch (_) {
        // 破棄後の`ref`の利用など。サーバー側の期限切れ（90秒）に任せる。
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
