import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/call.dart';
import '../../providers/chat_navigation_providers.dart';
import '../../repositories/call_repository.dart';
import '../../repositories/direct_message_repository.dart';
import '../../repositories/group_call_repository.dart';
import 'webrtc_call_controller.dart';
import 'webrtc_group_call_controller.dart';

/// 進行中の通話1件（1対1/広場のどちらか）。従来は`CallScreen`/
/// `GroupCallScreen`が`initState`でコントローラーを生成し`dispose`で
/// 破棄していた（＝通話の寿命が画面のマウント状態に紐づいていた）が、
/// PC埋め込み表示・ピン留めミニ表示・モバイルのドック化に対応するため、
/// コントローラーの所有者をこの[activeCallSessionProvider]（画面をまたいで
/// 生存する）へ移した（2026-08-19、通話UIの再設計に伴う）。
///
/// 通話中の細かい状態（ミュート・映像on/off等）は[controllerListenable]
/// （実体は各コントローラー自身、`ChangeNotifier`）を`ListenableBuilder`で
/// 直接listenして拾う（Riverpodの`state`はセッションの生成/終了/ドック状態
/// だけを表し、ミュート等の変化のたびに再代入はしない）。
sealed class ActiveCallSession {
  const ActiveCallSession({
    required this.conversation,
    required this.minimized,
  });

  /// この通話がどの会話（一対/広場）に属するか。埋め込み表示・ピン留め
  /// ミニ表示が「今その会話を見ているか」を判定するのに使う。
  final ViewedConversation conversation;

  /// モバイルで下スワイプしてドック（ミニ化）したか。
  final bool minimized;

  Listenable get controllerListenable;
  bool get isVideoLocallyOn;
  bool get hasAnyRemoteVideoOn;
  bool get hasEnded;
  Future<void> endCall();
  ActiveCallSession copyWithMinimized(bool value);
}

class OneToOneCallSession extends ActiveCallSession {
  OneToOneCallSession({
    required this.controller,
    required this.call,
    required this.isCaller,
    bool minimized = false,
  }) : super(conversation: ViewedDm(call.dmId), minimized: minimized);

  final WebrtcCallController controller;
  final Call call;
  final bool isCaller;

  String get currentUserId => isCaller ? call.callerId : call.calleeId;

  @override
  Listenable get controllerListenable => controller;

  @override
  bool get isVideoLocallyOn => controller.isVideo;

  @override
  bool get hasAnyRemoteVideoOn => controller.remoteIsVideo;

  @override
  bool get hasEnded => controller.state == CallConnectionState.ended;

  @override
  Future<void> endCall() => controller.hangUp();

  @override
  OneToOneCallSession copyWithMinimized(bool value) => OneToOneCallSession(
    controller: controller,
    call: call,
    isCaller: isCaller,
    minimized: value,
  );
}

class GroupCallSession extends ActiveCallSession {
  GroupCallSession({
    required this.controller,
    required this.groupCallId,
    required this.groupId,
    bool minimized = false,
  }) : super(conversation: ViewedGroup(groupId), minimized: minimized);

  final WebrtcGroupCallController controller;
  final String groupCallId;
  final String groupId;

  @override
  Listenable get controllerListenable => controller;

  @override
  bool get isVideoLocallyOn => controller.isVideo;

  @override
  bool get hasAnyRemoteVideoOn =>
      controller.remoteParticipants.any((p) => p.isVideo);

  @override
  bool get hasEnded => controller.state == GroupCallConnectionState.ended;

  @override
  Future<void> endCall() => controller.leave();

  @override
  GroupCallSession copyWithMinimized(bool value) => GroupCallSession(
    controller: controller,
    groupCallId: groupCallId,
    groupId: groupId,
    minimized: value,
  );
}

class ActiveCallSessionNotifier extends Notifier<ActiveCallSession?> {
  @override
  ActiveCallSession? build() => null;

  /// 1対1通話を開始/参加する。既に同じ通話にアタッチ済みならそのまま返す
  /// （冪等）。
  OneToOneCallSession startOneToOne({
    required Call call,
    required bool isCaller,
    required CallRepository callRepository,
    required DirectMessageRepository directMessageRepository,
  }) {
    final current = state;
    if (current is OneToOneCallSession && current.call.callId == call.callId) {
      return current;
    }
    final controller = WebrtcCallController(
      call: call,
      isCaller: isCaller,
      callRepository: callRepository,
      directMessageRepository: directMessageRepository,
    );
    final session = OneToOneCallSession(
      controller: controller,
      call: call,
      isCaller: isCaller,
    );
    controller.addListener(() => _onControllerChanged(session));
    controller.initialize();
    if (!isCaller) controller.soundPlayer.startRingtoneLoop();
    state = session;
    return session;
  }

  /// 広場通話を開始/参加する。既に同じ通話にアタッチ済みならそのまま返す。
  GroupCallSession startGroup({
    required String groupCallId,
    required String groupId,
    required AppUser currentUser,
    required bool isVideo,
    required GroupCallRepository groupCallRepository,
  }) {
    final current = state;
    if (current is GroupCallSession && current.groupCallId == groupCallId) {
      return current;
    }
    final controller = WebrtcGroupCallController(
      groupCallId: groupCallId,
      currentUser: currentUser,
      isVideo: isVideo,
      groupCallRepository: groupCallRepository,
    );
    final session = GroupCallSession(
      controller: controller,
      groupCallId: groupCallId,
      groupId: groupId,
    );
    controller.addListener(() => _onControllerChanged(session));
    controller.initialize();
    state = session;
    return session;
  }

  void _onControllerChanged(ActiveCallSession session) {
    // 通話が既に別のセッションへ入れ替わっている（＝このリスナーは古い
    // コントローラーのもの）場合は何もしない。
    if (!identical(state, session) && state != session) return;
    if (session.hasEnded) _teardown(session);
  }

  void _teardown(ActiveCallSession session) {
    if (state == session) state = null;
    switch (session) {
      case OneToOneCallSession(:final controller):
        controller.soundPlayer.stopRingtone();
        controller.dispose();
      case GroupCallSession(:final controller):
        controller.dispose();
    }
  }

  /// 通話を終了する（1対1: 切断、広場: 退出）。実際のセッション破棄は
  /// コントローラー側の状態がended化するのを検知した[_onControllerChanged]
  /// が行う。
  Future<void> endCall() async {
    final session = state;
    if (session == null) return;
    await session.endCall();
  }

  void setMinimized(bool value) {
    final session = state;
    if (session == null || session.minimized == value) return;
    state = session.copyWithMinimized(value);
  }
}

final activeCallSessionProvider =
    NotifierProvider<ActiveCallSessionNotifier, ActiveCallSession?>(
      ActiveCallSessionNotifier.new,
    );
