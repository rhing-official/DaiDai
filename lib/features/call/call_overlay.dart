import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/camera_availability_provider.dart';
import '../../utils/platform_info.dart';
import '../../widgets/swipe_gestures.dart';
import 'active_call_session.dart';
import 'call_audio_sinks.dart';
import 'call_avatar.dart';
import '../../providers/call_bgm_provider.dart';
import 'bgm/call_bgm_bindings.dart';
import 'screen_share_menu.dart';
import 'call_control_bar.dart';
import 'call_video_viewer.dart';
import 'call_pin_provider.dart';
import 'call_tile_layout.dart';
import 'camera_availability.dart';
import 'webrtc_call_controller.dart';
import 'webrtc_group_call_controller.dart';
import '../../router/back_stack.dart';
import '../../l10n/strings.dart';

/// PC・Web: 通話画面を、今見ている画面の**上に重ねて**表示する層（2026-10-23、
/// 以前は通話中の語らいを開いてメッセージ表示を通話UIに差し替える
/// `EmbeddedCallPane`だった）。`main.dart`の`builder`で全ルートの上に常時
/// マウントし、通話セッションがあり[callOverlayOpenProvider]が`true`の間だけ
/// 画面いっぱいに出す。閉じると右上のミニ表示（`PinnedCallOverlay`）に戻り、
/// 重ねる前の画面（スクロール位置・入力途中の内容を含む）がそのまま見える。
/// スマホアプリは全画面ルート（`/call`・`/group-call`）を重ねる従来の方式で、
/// この層は出さない。
class CallOverlay extends ConsumerWidget {
  const CallOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeCallSessionProvider);
    final open = ref.watch(callOverlayOpenProvider);
    if (isMobileCallPlatform || session == null || !open) {
      return const SizedBox.shrink();
    }
    // `MaterialApp.builder`の位置にはNavigator・Overlayが無く、`Tooltip`等が
    // 使えない為、専用の`Overlay`を持つ。
    return Positioned.fill(
      child: Overlay(
        initialEntries: [
          OverlayEntry(builder: (context) => const _CallOverlayBody()),
        ],
      ),
    );
  }
}

/// 通話画面（[CallOverlay]）が開いている間、その下の画面のフォーカスを全て外し、
/// フォーカスを受けられないようにする（2026-11-03）。Webは入力欄にフォーカスがあると、
/// ブラウザの入力要素がキャンバスの上に出て、そのプレースホルダー（「メッセージを入力...」）
/// が、ぼかしや暗幕を貫通して、Flutter側の文字と二重に見えてしまうため。
/// 通話画面の`MaterialApp.builder`の子（アプリ本体）を包む。
class CallOverlayFocusGuard extends ConsumerWidget {
  const CallOverlayFocusGuard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open =
        !isMobileCallPlatform &&
        ref.watch(activeCallSessionProvider) != null &&
        ref.watch(callOverlayOpenProvider);
    // 開閉で木の形が変わらないよう、常に包む（`excluding`だけを切り替える）。
    return ExcludeFocus(excluding: open, child: child);
  }
}

class _CallOverlayBody extends ConsumerWidget {
  const _CallOverlayBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeCallSessionProvider);
    if (session == null) return const SizedBox.shrink();
    void close() => ref.read(callOverlayOpenProvider.notifier).close();
    // Webでは映像（プラットフォームビュー）がクリックを奪うため、重ねた面が
    // 受け取れるようにする。ブラウザの戻る・Escで閉じられる。
    // 通話画面は、少し狭い角丸のポップアップにする（2026-11-03）。周りの余白は、画像の
    // 拡大表示（`blurredViewerRoute`）と同じぼかし＋暗幕で半透明にし、クリックすると
    // ミニ表示になる（通話は続く）。影は使わない。
    return PointerInterceptor(
      child: BackEntry(
        scope: null,
        active: true,
        layer: true,
        onBack: close,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // ピン留めしたウィンドウがあれば、外（余白）のクリックでまずピンを外す。
              onTap: () {
                final pins = ref.read(callPinnedTilesProvider.notifier);
                if (ref.read(callPinnedTilesProvider).isNotEmpty) {
                  pins.clear();
                } else {
                  close();
                }
              },
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
              ),
            ),
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.88,
                heightFactor: 0.94,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: CallOverlayView(session: session, onClose: close),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 通話UI本体（ヘッダー・ステージ・コントロール）。
class CallOverlayView extends StatefulWidget {
  const CallOverlayView({required this.session, required this.onClose});

  final ActiveCallSession session;
  final VoidCallback onClose;

  @override
  State<CallOverlayView> createState() => _CallOverlayViewState();
}

class _CallOverlayViewState extends State<CallOverlayView> {
  /// 通話画面のキー入力（Esc）を受けるフォーカス。開いた直後に、下のメッセージ画面の
  /// 入力欄から奪う（2026-11-03）。Webは入力欄にフォーカスがあると、ブラウザの入力要素が
  /// キャンバスの上に出て、そのプレースホルダー（「メッセージを入力...」）が、ぼかしや暗幕を
  /// 貫通して見えてしまうため。
  final FocusNode _focusNode = FocusNode(debugLabel: 'call-overlay');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 映像（又はその代役のプレースホルダー）の領域は各Stageが固定グレーで塗る。
    // その外側（ボタン列の周り）は面を塗らず、周りの余白と同じ見た目にする（2026-11-03）。
    return ListenableBuilder(
      listenable: widget.session.controllerListenable,
      builder: (context, _) {
        // 通話画面の座標上のどこでも、左上のボタン（`_Header`の
        // `expand_more`）を押すのと同じ「メッセージに戻る」動作を、上
        // スクロール（マウスホイール/トラックパッド）・下スワイプ
        // （タッチ・マウスドラッグ）どちらからでも行えるようにする
        // （2026-08-30追加）。
        return Focus(
          // Escでも「メッセージに戻る」（2026-10-11追加）。通話UI表示中は入力欄が
          // 無い為、キーを受けるだけのフォーカスを取る。
          autofocus: true,
          focusNode: _focusNode,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              widget.onClose();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          // 上スクロールでミニ表示にする操作は廃止した（2026-11-03、ユーザー指示。映像の
          // 拡大表示がホイール操作で閉じてしまうため）。
          child: SwipeDownToDismiss(
            onDismiss: widget.onClose,
            // `Material`祖先が無いと`Text`が`DefaultTextStyle`を得られず、
            // 48px・白・黄色の二重下線のフォールバック表示になる（2026-10-13修正）。
            child: Material(
              // 面の色は付けない（2026-11-03）。映像・アイコンの領域（角丸）だけが
              // 通話画面で、その下のボタン列は周りの余白（ぼかし）の上に直接置く。
              // ボタン以外の部分は余白として扱い、クリックするとミニ表示になる。
              type: MaterialType.transparency,
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: switch (widget.session) {
                        OneToOneCallSession s => _OneToOneStage(session: s),
                        GroupCallSession s => _GroupStage(session: s),
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: _EmbeddedControls(session: widget.session),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OneToOneStage extends ConsumerStatefulWidget {
  const _OneToOneStage({required this.session});
  final OneToOneCallSession session;

  @override
  ConsumerState<_OneToOneStage> createState() => _OneToOneStageState();
}

class _OneToOneStageState extends ConsumerState<_OneToOneStage> {
  /// 拡大表示（画像・動画・PDFと同じぼかしの拡大、2026-11-03）を閉じるたびに増やし、
  /// 映像の部品を作り直す（Webの描画要素は拡大側へ移る為、元の映像が空になる）。
  int _viewerGeneration = 0;

  /// ウィンドウの映像を拡大表示する（ウィンドウのタップ）。
  void _openViewer(RTCVideoRenderer renderer, {required bool mirror}) {
    showCallVideoViewer(
      context,
      renderer: renderer,
      mirror: mirror,
      onClosed: () {
        if (mounted) setState(() => _viewerGeneration++);
      },
    );
  }

  /// 映像が無い側の枠に出す、その人のプロフィールアイコン（2026-10-21追加）。
  /// [remote]が相手、falseなら自分。
  Widget _avatar({required bool remote, required double radius}) {
    final session = widget.session;
    final call = session.call;
    final me = session.currentUserId;
    return CallParticipantAvatar(
      userId: remote ? call.otherUserId(me) : me,
      rhingSeed: remote ? call.otherRhingSeed(me) : call.myRhingSeed(me),
      conversationId: call.dmId,
      radius: radius,
      fontSize: radius * 0.7,
    );
  }

  /// 1人ぶんのタイル（映像、無ければアイコン。呼び名とミュート表示つき）。[pinned]は
  /// ピン留めで大きく出している時。
  Widget _participantTile({required bool remote, required bool pinned}) {
    final session = widget.session;
    final controller = session.controller;
    final call = session.call;
    final me = session.currentUserId;
    final hasVideo = remote ? controller.remoteVideoShown : controller.isVideo;
    final renderer = remote
        ? controller.remoteRenderer
        : controller.localRenderer;
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCallTileRadius),
      child: Container(
        color: Colors.grey.shade900,
        child: Stack(
          fit: StackFit.expand,
          children: [
            hasVideo
                ? RTCVideoView(
                    key: ValueKey((renderer, _viewerGeneration)),
                    renderer,
                    mirror: !remote && controller.isFrontCamera,
                    objectFit: pinned
                        ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                        : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : Center(
                    child: _avatar(remote: remote, radius: pinned ? 56 : 28),
                  ),
            Positioned(
              left: 8,
              bottom: 8,
              child: IgnorePointer(
                child: CallLabelSheet(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CallParticipantNameLabel(
                        userId: remote ? call.otherUserId(me) : me,
                        rhingSeed: remote
                            ? call.otherRhingSeed(me)
                            : call.myRhingSeed(me),
                        conversationId: call.dmId,
                        style: const TextStyle(
                          color: Colors.white,
                          shadows: [Shadow(blurRadius: 6)],
                        ),
                      ),
                      if (remote ? controller.remoteMuted : controller.muted)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.mic_off,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 画面共有の中のタイル（共有の画面。ライブ・画質つき）。
  Widget _screenTile({required bool remote}) {
    final session = widget.session;
    final controller = session.controller;
    final strings = ref.watch(appStringsProvider);
    final call = session.call;
    final me = session.currentUserId;
    final renderer = remote
        ? controller.remoteScreenRenderer
        : controller.localScreenRenderer;
    return ScreenShareFrame(
      video: RTCVideoView(
        key: ValueKey((renderer, _viewerGeneration)),
        renderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      ),
      name: CallParticipantNameLabel(
        userId: remote ? call.otherUserId(me) : me,
        rhingSeed: remote ? call.otherRhingSeed(me) : call.myRhingSeed(me),
        conversationId: call.dmId,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      qualityLabel: remote
          ? (controller.remoteScreenLabel ?? '')
          : controller.screenQuality.label,
      liveText: strings.callScreenShareLive,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.session.controller;
    // ウィンドウ（共有は1枚と数え、先頭＝最上行。2026-11-16、広場と同じ並べ方・ピン留め）。
    final specs = [
      if (controller.remoteScreenShown)
        CallTileSpec(
          key: 'remote#screen',
          onTap: () =>
              _openViewer(controller.remoteScreenRenderer, mirror: false),
          build: (_) => _screenTile(remote: true),
        ),
      if (controller.isScreenSharing)
        CallTileSpec(
          key: 'self#screen',
          onTap: () =>
              _openViewer(controller.localScreenRenderer, mirror: false),
          build: (_) => _screenTile(remote: false),
        ),
      CallTileSpec(
        key: 'self',
        onTap: controller.isVideo
            ? () => _openViewer(
                controller.localRenderer,
                mirror: controller.isFrontCamera,
              )
            : null,
        build: (pinned) => _participantTile(remote: false, pinned: pinned),
      ),
      CallTileSpec(
        key: 'remote',
        onTap: controller.remoteVideoShown
            ? () => _openViewer(controller.remoteRenderer, mirror: false)
            : null,
        build: (pinned) => _participantTile(remote: true, pinned: pinned),
      ),
    ];
    // 相手の映像のタイルが無い時は、相手の音声を鳴らす見えない動画要素で補う
    // （Webは`RTCVideoView`が音を鳴らす、2026-10-31追加）。
    final audioSink = controller.remoteVideoShown
        ? const SizedBox.shrink()
        : CallAudioSinks(renderers: [controller.remoteRenderer]);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: CallTileStage(specs: specs)),
        Positioned(left: 0, top: 0, child: audioSink),
      ],
    );
  }
}

class _GroupStage extends ConsumerStatefulWidget {
  const _GroupStage({required this.session});
  final GroupCallSession session;

  @override
  ConsumerState<_GroupStage> createState() => _GroupStageState();
}

class _GroupStageState extends ConsumerState<_GroupStage> {
  /// 拡大表示を閉じるたびに増やし、映像の部品を作り直す（Webの描画要素は拡大側へ移る為）。
  int _viewerGeneration = 0;

  GroupCallSession get session => widget.session;

  void _openViewer(RTCVideoRenderer renderer, {required bool mirror}) {
    showCallVideoViewer(
      context,
      renderer: renderer,
      mirror: mirror,
      onClosed: () {
        if (mounted) setState(() => _viewerGeneration++);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = session.controller;
    final selfId = controller.currentUser.userId;
    final remotes = controller.remoteParticipants;
    final strings = ref.watch(appStringsProvider);

    CallTileSpec screenSpec({
      required String userId,
      required String rhingSeed,
      required RTCVideoRenderer renderer,
      required String label,
    }) {
      return CallTileSpec(
        key: '$userId#screen',
        onTap: () => _openViewer(renderer, mirror: false),
        build: (_) => ScreenShareFrame(
          video: RTCVideoView(
            key: ValueKey((renderer, _viewerGeneration)),
            renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          ),
          name: CallParticipantNameLabel(
            userId: userId,
            rhingSeed: rhingSeed,
            conversationId: session.groupId,
            style: const TextStyle(
              color: Colors.white,
              shadows: [Shadow(blurRadius: 6)],
            ),
          ),
          qualityLabel: label,
          liveText: strings.callScreenShareLive,
        ),
      );
    }

    CallTileSpec personSpec({
      required String userId,
      required String rhingSeed,
      required RTCVideoRenderer? renderer,
      required bool mirror,
      required bool videoEnabled,
      required bool micMuted,
    }) {
      return CallTileSpec(
        key: userId,
        onTap: videoEnabled && renderer != null
            ? () => _openViewer(renderer, mirror: mirror)
            : null,
        build: (pinned) => _tile(
          userId: userId,
          rhingSeed: rhingSeed,
          renderer: renderer,
          mirror: mirror,
          videoEnabled: videoEnabled,
          micMuted: micMuted,
          focused: pinned,
        ),
      );
    }

    // ウィンドウ（画面共有は1枚と数え、先頭＝最上行。2026-11-16）。
    final specs = <CallTileSpec>[
      if (controller.isScreenSharing)
        screenSpec(
          userId: selfId,
          rhingSeed: controller.currentUser.rhingSeed,
          renderer: controller.localScreenRenderer,
          label: controller.screenQuality.label,
        ),
      for (final p in remotes)
        if (controller.remoteScreenShown(p))
          screenSpec(
            userId: p.userId,
            rhingSeed: p.rhingSeed,
            renderer: controller.screenRenderers[p.userId]!,
            label: p.screenLabel ?? '',
          ),
      personSpec(
        userId: selfId,
        rhingSeed: controller.currentUser.rhingSeed,
        renderer: controller.isVideo ? controller.localRenderer : null,
        mirror: controller.isFrontCamera,
        videoEnabled: controller.isVideo,
        micMuted: controller.muted,
      ),
      for (final p in remotes)
        personSpec(
          userId: p.userId,
          rhingSeed: p.rhingSeed,
          renderer: controller.remoteRenderers[p.userId],
          mirror: false,
          videoEnabled: controller.remoteVideoShown(p),
          micMuted: p.micMuted,
        ),
    ];

    // 映像のタイルを画面に出していない参加者の音声を鳴らす、見えない動画要素
    // （2026-10-21追加、映像オフの参加者の音声がWebで聞こえなかった）。
    final audioIds = groupAudioOnlyUserIds(
      remoteIds: [for (final p in remotes) p.userId],
      videoOnIds: {
        for (final p in remotes)
          if (controller.remoteVideoShown(p)) p.userId,
      },
    );
    final audioOnly = [
      for (final id in audioIds)
        if (controller.remoteRenderers[id] != null)
          controller.remoteRenderers[id]!,
    ];

    return Stack(
      children: [
        Positioned.fill(child: CallTileStage(specs: specs)),
        Positioned(
          left: 0,
          top: 0,
          child: CallAudioSinks(renderers: audioOnly),
        ),
      ],
    );
  }

  Widget _tile({
    required String userId,
    required String rhingSeed,
    required RTCVideoRenderer? renderer,
    required bool mirror,
    required bool videoEnabled,
    required bool micMuted,
    required bool focused,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCallTileRadius),
      child: Container(
        color: Colors.grey.shade900,
        child: Stack(
          fit: StackFit.expand,
          children: [
            videoEnabled && renderer != null
                ? RTCVideoView(
                    key: ValueKey((renderer, _viewerGeneration)),
                    renderer,
                    mirror: mirror,
                    // ピン留め中は映像全体を見せる（余白は灰色）、グリッドは枠いっぱい。
                    objectFit: focused
                        ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                        : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : Center(
                    child: CallParticipantAvatar(
                      userId: userId,
                      rhingSeed: rhingSeed,
                      conversationId: session.groupId,
                      radius: focused ? 56 : 28,
                      fontSize: focused ? 40 : null,
                    ),
                  ),
            // 表示領域の左下に呼び名、ミュート中はその右隣にミュートアイコンを
            // 表示する（2026-08-31追加、`group_call_screen.dart`の
            // `_videoTile`と同じ並び順・見た目に揃える）。
            Positioned(
              left: 8,
              bottom: 8,
              child: CallLabelSheet(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CallParticipantNameLabel(
                      userId: userId,
                      rhingSeed: rhingSeed,
                      conversationId: session.groupId,
                      style: const TextStyle(
                        color: Colors.white,
                        shadows: [Shadow(blurRadius: 6)],
                      ),
                    ),
                    if (micMuted) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.mic_off, size: 14, color: Colors.white),
                    ],
                  ],
                ),
              ),
            ),
            if (session.controller.speakingUserIds.contains(userId))
              Positioned.fill(child: SpeakingFrame()),
          ],
        ),
      ),
    );
  }
}

class _EmbeddedControls extends ConsumerWidget {
  const _EmbeddedControls({required this.session});
  final ActiveCallSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final cameraAvailability =
        ref.watch(cameraAvailabilityProvider).value ??
        CameraAvailability.unknown;
    return switch (session) {
      OneToOneCallSession(:final controller, :final currentUserId) =>
        CallControlBar(
          isGekiga: isGekiga,
          isGlass: isGlass,
          enabled: controller.state == CallConnectionState.active,
          muted: controller.muted,
          onToggleMute: controller.toggleMute,
          speakerOn: controller.speakerOn,
          onToggleSpeaker: controller.toggleSpeaker,
          showSpeakerToggle: controller.showSpeakerToggle,
          switchingCallType: controller.switchingCallType,
          onToggleVideoType:
              cameraAvailability == CameraAvailability.unavailable
              ? null
              : () => controller.setVideoEnabled(!controller.isVideo),
          isVideo: controller.isVideo,
          hasMultipleCameras: controller.hasMultipleCameras,
          switchingCamera: controller.switchingCamera,
          onSwitchCamera: controller.switchCamera,
          onHangUp: controller.hangUp,
          bgmBinding: oneToOneBgmBinding(controller),
          screenShare: oneToOneScreenShare(controller, currentUserId),
          remoteBgm: controller.remoteBgm,
          videoFailed: controller.videoFailed,
        ),
      GroupCallSession(:final controller, :final groupId) => CallControlBar(
        isGekiga: isGekiga,
        isGlass: isGlass,
        enabled: controller.state == GroupCallConnectionState.active,
        muted: controller.muted,
        onToggleMute: controller.toggleMute,
        speakerOn: controller.speakerOn,
        onToggleSpeaker: controller.toggleSpeaker,
        showSpeakerToggle: controller.showSpeakerToggle,
        switchingCallType: controller.switchingCallType,
        onToggleVideoType: cameraAvailability == CameraAvailability.unavailable
            ? null
            : () => controller.setVideoEnabled(!controller.isVideo),
        isVideo: controller.isVideo,
        hasMultipleCameras: controller.hasMultipleCameras,
        switchingCamera: controller.switchingCamera,
        onSwitchCamera: controller.switchCamera,
        onHangUp: () => controller.leave(),
        videoFailed: controller.videoFailed,
        remoteBgm: controller.remoteBgm,
        screenShare: groupScreenShare(controller),
        bgmBinding: groupBgmBinding(
          controller,
          allowed: ref.watch(
            canPlayCallBgmProvider((
              groupId: groupId,
              userId: controller.currentUser.userId,
            )),
          ),
        ),
      ),
    };
  }
}
