import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/locked_call_providers.dart';
import '../../providers/ring_launch_provider.dart';
import '../../router/app_router.dart';
import 'active_call_session.dart';
import 'webrtc_call_controller.dart';

const _channel = MethodChannel('jp.rhing.daidai/call_action');

/// 端末のロック画面の上でアプリを開いた着信・通話の、安全のための層（Android、2026-11-18）。
///
/// - 通話・着信が**終わったら**（拒否・不在・終話・取消を含む）、ロック画面の上の表示をやめ、
///   端末の認証（生体認証など）を求める。以前は、ホームボタンを押すまで、認証なしでアプリの
///   他の操作ができてしまっていた。
/// - 端末がロックされたままの**通話中**は、通常の通話画面のまま使える（画面共有・映像も見える）。
///   通話画面から出る操作（下スワイプ・戻る）は、先に端末の認証（生体認証など）を求める。
///   ホームボタンは、OSがロック画面を出すので、認証するまで他の操作はできない。
class LockScreenCallGuard extends ConsumerStatefulWidget {
  const LockScreenCallGuard({super.key});

  @override
  ConsumerState<LockScreenCallGuard> createState() =>
      _LockScreenCallGuardState();
}

class _LockScreenCallGuardState extends ConsumerState<LockScreenCallGuard> {
  static bool get _supported => !kIsWeb && Platform.isAndroid;

  Timer? _poll;
  bool _locked = false;
  bool _hadActivity = false;
  bool _blocking = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      // 想定外の環境。何もしない。
    } on PlatformException {
      // 同上。
    }
  }

  Future<void> _checkLocked() async {
    if (!_supported) return;
    try {
      final locked =
          await _channel.invokeMethod<bool>('isDeviceLocked') ?? false;
      if (mounted && locked != _locked) setState(() => _locked = locked);
    } on MissingPluginException {
      // 何もしない。
    } on PlatformException {
      // 何もしない。
    }
  }

  /// 通話・着信の有無が変わった時に呼ぶ。
  void _sync() {
    if (!_supported) return;
    final active =
        ref.read(activeCallSessionProvider) != null ||
        ref.read(ringLaunchProvider) != null;
    if (active) {
      _hadActivity = true;
      _poll ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) => _checkLocked(),
      );
      _checkLocked();
    } else if (_hadActivity) {
      _hadActivity = false;
      _poll?.cancel();
      _poll = null;
      if (_locked) setState(() => _locked = false);
      _setBlocking(false);
      // ロック画面の上の表示をやめ、端末の認証を求める。
      _invoke('releaseOverLock');
    }
  }

  void _setBlocking(bool on) {
    if (_blocking == on) return;
    _blocking = on;
    _invoke('setLockedCallMode', {'on': on});
  }

  /// 着信中（まだ応答していない）は、全画面の応答/拒否が出るので、ここでは出さない。
  bool _isIncomingRinging(ActiveCallSession session) {
    if (session is OneToOneCallSession) {
      final c = session.controller;
      return !c.isCaller &&
          !c.accepting &&
          c.state == CallConnectionState.connecting;
    }
    return false;
  }

  /// 通話画面が最前面でなければ前面に出す（通話ごとに1回）。
  String? _ensuredFor;

  void _ensureCallScreen(ActiveCallSession session) {
    final key = switch (session) {
      OneToOneCallSession(:final call) => call.callId,
      GroupCallSession(:final groupCallId) => groupCallId,
    };
    if (_ensuredFor == key) return;
    _ensuredFor = key;
    if (session.minimized) {
      ref.read(activeCallSessionProvider.notifier).setMinimized(false);
    }
    final router = ref.read(goRouterProvider);
    final top =
        router.routerDelegate.currentConfiguration.lastOrNull?.matchedLocation;
    switch (session) {
      case final OneToOneCallSession one:
        if (top != '/call') {
          router.push(
            '/call',
            extra: CallArgs(
              call: one.call,
              isCaller: one.isCaller,
              currentUserId: one.currentUserId,
            ),
          );
        }
      case final GroupCallSession group:
        if (top != '/group-call') {
          router.push(
            '/group-call',
            extra: GroupCallArgs(
              groupCallId: group.groupCallId,
              groupId: group.groupId,
              currentUser: group.controller.currentUser,
              isVideo: group.controller.isVideo,
            ),
          );
        }
    }
  }

  void _applyMode(bool on, ActiveCallSession? session) {
    ref.read(lockedCallModeProvider.notifier).set(on);
    _setBlocking(on);
    if (on && session != null) {
      _ensureCallScreen(session);
    } else if (!on) {
      _ensuredFor = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    ref.listen(activeCallSessionProvider, (_, _) => _sync());
    ref.listen(ringLaunchProvider, (_, _) => _sync());
    final session = ref.watch(activeCallSessionProvider);
    if (!_locked || session == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? _applyMode(false, null) : null,
      );
      return const SizedBox.shrink();
    }
    // ロック中の通話は、通常の通話画面のまま使える。画面から出る操作だけ、認証を求める。
    return ListenableBuilder(
      listenable: session.controllerListenable,
      builder: (context, _) {
        final on = !_isIncomingRinging(session) && !session.hasEnded;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => mounted ? _applyMode(on, session) : null,
        );
        return const SizedBox.shrink();
      },
    );
  }
}
