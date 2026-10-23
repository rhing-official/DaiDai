import 'dart:async';

import 'package:flutter/gestures.dart';
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
import 'call_control_bar.dart';
import 'call_tile_layout.dart';
import 'call_controls.dart';
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
    // 使えないため、専用の`Overlay`を持つ。
    return Positioned.fill(
      child: Overlay(
        initialEntries: [
          OverlayEntry(builder: (context) => const _CallOverlayBody()),
        ],
      ),
    );
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
    return PointerInterceptor(
      child: BackEntry(
        scope: null,
        active: true,
        layer: true,
        onBack: close,
        child: CallOverlayView(session: session, onClose: close),
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
  /// マウスホイール/トラックパッドでの上スクロール終了のデバウンス用
  /// タイマー（2026-08-30追加、`chat_screen.dart`のメディアビューアと同じ
  /// パターン。1回のトラックパッド操作で多数の`PointerScrollEvent`が連続
  /// して届くため、即座に[VoidCallback]を呼ぶと残りのイベントが遷移後の
  /// メッセージ一覧側へ漏れて意図せずスクロールしてしまう不具合を避ける）。
  Timer? _scrollBackTimer;

  @override
  void dispose() {
    _scrollBackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 表示領域以外（ヘッダー・コントロール周りを含むこのパネル全体の背景）は
    // 常にテーマの背景色にする（2026-08-30更新、以前はガラスUIのみだったが
    // 3スタイル共通にした）。表示領域自体（映像 or その代役の
    // プレースホルダー）は各Stageが常に固定グレーを使う。
    final colorScheme = Theme.of(context).colorScheme;
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
          // 無いため、キーを受けるだけのフォーカスを取る。
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              widget.onClose();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && event.scrollDelta.dy < -2.0) {
                _scrollBackTimer?.cancel();
                _scrollBackTimer = Timer(const Duration(milliseconds: 150), () {
                  if (mounted) widget.onClose();
                });
              }
            },
            child: SwipeDownToDismiss(
              onDismiss: widget.onClose,
              // `Material`祖先が無いと`Text`が`DefaultTextStyle`を得られず、
              // 48px・白・黄色の二重下線のフォールバック表示になる（2026-10-13修正）。
              child: Material(
                color: colorScheme.surface,
                child: Column(
                  children: [
                    _Header(onClose: widget.onClose),
                    Expanded(
                      child: switch (widget.session) {
                        OneToOneCallSession s => _OneToOneStage(session: s),
                        GroupCallSession s => _GroupStage(session: s),
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: _EmbeddedControls(session: widget.session),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.expand_more, color: Colors.white),
              tooltip: '',
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _OneToOneStage extends StatefulWidget {
  const _OneToOneStage({required this.session});
  final OneToOneCallSession session;

  @override
  State<_OneToOneStage> createState() => _OneToOneStageState();
}

class _OneToOneStageState extends State<_OneToOneStage> {
  /// 大きく表示している（メインの）映像が相手か自分か（2026-10-13追加）。
  /// 右下の小さい映像（コーナー）をクリックすると入れ替わり、入れ替えた後に
  /// メインをクリックすれば元に戻る（`call_screen.dart`の`_mainViewIsRemote`と
  /// 同じ規則）。
  bool _mainIsRemote = true;

  void _swap() => setState(() => _mainIsRemote = !_mainIsRemote);

  /// 映像が無い側の枠に出す、その人のプロフィールアイコン（2026-10-21追加）。
  /// 片方だけ映像をオンにすると、オフの側の枠が空白になり誰か分からなく
  /// なっていた。[remote]が相手、falseなら自分。
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

  /// 映像の描画。メインは切り抜かず全体を見せ（Contain、余白は灰色。2026-10-11
  /// 変更）、コーナーは枠いっぱいに切り抜く（Cover）。自分の映像は前面カメラの
  /// 時だけ左右反転する（どちらの位置でも同じ）。
  Widget _video({required bool remote, required bool main}) {
    final controller = widget.session.controller;
    final renderer = remote
        ? controller.remoteRenderer
        : controller.localRenderer;
    return RTCVideoView(
      // Web版の`RTCVideoView`はinitState時にしか描画要素を取らないため、
      // レンダラー自体をキーにして入れ替え時に確実に作り直す。
      key: ObjectKey(renderer),
      renderer,
      mirror: !remote && controller.isFrontCamera,
      objectFit: main
          ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
          : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final controller = session.controller;
    if (!controller.remoteIsVideo && !controller.isVideo) {
      return ColoredBox(
        color: Colors.grey.shade900,
        child: Center(
          child: CallParticipantAvatar(
            userId: session.call.otherUserId(session.currentUserId),
            rhingSeed: session.call.otherRhingSeed(session.currentUserId),
            conversationId: session.call.dmId,
            radius: 56,
            fontSize: 40,
          ),
        ),
      );
    }
    final mainHasVideo = _mainIsRemote
        ? controller.remoteIsVideo
        : controller.isVideo;
    final cornerHasVideo = _mainIsRemote
        ? controller.isVideo
        : controller.remoteIsVideo;
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: Colors.grey.shade900,
            child: mainHasVideo
                ? _video(remote: _mainIsRemote, main: true)
                : Center(child: _avatar(remote: _mainIsRemote, radius: 56)),
          ),
        ),
        // メインの画面をクリックしても入れ替わる。Webでは映像（プラット
        // フォームビュー）がクリックを奪うため`PointerInterceptor`で受ける。
        Positioned.fill(
          child: PointerInterceptor(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _swap,
              child: const SizedBox.expand(),
            ),
          ),
        ),
        // 映像が無い側も小窓を出し、その人のアイコンを入れる（2026-10-21変更、
        // 以前は映像がある時だけ出していたため、オフの側が消えていた）。
        Positioned(
          right: 12,
          bottom: 12,
          child: PointerInterceptor(
            child: GestureDetector(
              onTap: _swap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 80,
                  height: 110,
                  child: cornerHasVideo
                      ? _video(remote: !_mainIsRemote, main: false)
                      : ColoredBox(
                          color: Colors.grey.shade800,
                          child: Center(
                            child: _avatar(remote: !_mainIsRemote, radius: 28),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
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
  /// 通話エリアいっぱいに拡大している参加者（自分も可、nullならグリッド、
  /// 2026-10-21追加）。タイルのクリックで拡大し、もう一度クリック・戻るボタン・
  /// Escでグリッドへ戻る。モバイルの全画面通話画面（`group_call_screen.dart`の
  /// `_focusedTileKey`）と同じ考え方。
  String? _focusedUserId;

  GroupCallSession get session => widget.session;

  @override
  Widget build(BuildContext context) {
    final controller = session.controller;
    final selfId = controller.currentUser.userId;
    final remotes = controller.remoteParticipants;
    // 拡大中の参加者が退出したら、グリッドへ戻る。
    final focusedId =
        _focusedUserId != null &&
            (_focusedUserId == selfId ||
                remotes.any((p) => p.userId == _focusedUserId))
        ? _focusedUserId
        : null;

    Widget tileFor({
      required String userId,
      required String rhingSeed,
      required RTCVideoRenderer? renderer,
      required bool mirror,
      required bool videoEnabled,
      required bool micMuted,
      required bool focused,
    }) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _tile(
            userId: userId,
            rhingSeed: rhingSeed,
            renderer: renderer,
            mirror: mirror,
            videoEnabled: videoEnabled,
            micMuted: micMuted,
            focused: focused,
          ),
          // Webでは映像（プラットフォームビュー）がクリックを奪うため、
          // `PointerInterceptor`で受けて、拡大・拡大の解除を切り替える。
          Positioned.fill(
            child: PointerInterceptor(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    setState(() => _focusedUserId = focused ? null : userId),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
    }

    final entries = <({String userId, Widget Function(bool focused) build})>[
      (
        userId: selfId,
        build: (focused) => tileFor(
          userId: selfId,
          rhingSeed: controller.currentUser.rhingSeed,
          renderer: controller.isVideo ? controller.localRenderer : null,
          mirror: controller.isFrontCamera,
          videoEnabled: controller.isVideo,
          micMuted: controller.muted,
          focused: focused,
        ),
      ),
      for (final p in remotes)
        (
          userId: p.userId,
          build: (focused) => tileFor(
            userId: p.userId,
            rhingSeed: p.rhingSeed,
            renderer: controller.remoteRenderers[p.userId],
            mirror: false,
            videoEnabled: p.isVideo,
            micMuted: p.micMuted,
            focused: focused,
          ),
        ),
    ];

    // 映像のタイルを画面に出していない参加者の音声を鳴らす、見えない動画要素
    // （2026-10-21追加、映像オフの参加者の音声がWebで聞こえなかった。拡大中は
    // 拡大している1人以外のタイルが無いため、他の映像の参加者の音声も鳴らす）。
    final audioIds = groupAudioOnlyUserIds(
      remoteIds: [for (final p in remotes) p.userId],
      videoOnIds: {
        for (final p in remotes)
          if (p.isVideo) p.userId,
      },
      focusedUserId: focusedId,
    );
    final audioOnly = [
      for (final id in audioIds)
        if (controller.remoteRenderers[id] != null)
          controller.remoteRenderers[id]!,
    ];

    final Widget stage;
    if (focusedId != null) {
      final focusedEntry = entries.firstWhere((e) => e.userId == focusedId);
      final strings = ref.watch(appStringsProvider);
      stage = Focus(
        // Escで、通話エリアの拡大だけを解除する（親の「メッセージに戻る」より先に
        // 受ける）。
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            setState(() => _focusedUserId = null);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            focusedEntry.build(true),
            Positioned(
              top: 8,
              right: 8,
              child: PointerInterceptor(
                child: IconButton(
                  tooltip: strings.groupCallBackToGridTooltip,
                  icon: const Icon(
                    Icons.close_fullscreen,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 6)],
                  ),
                  onPressed: () => setState(() => _focusedUserId = null),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // 領域が縦長（スマホ等）なら縦に積み、横長なら従来のグリッド
      // （`CallTileGrid`、2026-10-13）。
      stage = CallTileGrid(tiles: [for (final e in entries) e.build(false)]);
    }

    return Stack(
      children: [
        Positioned.fill(child: stage),
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
    return Container(
      color: Colors.grey.shade900,
      child: Stack(
        fit: StackFit.expand,
        children: [
          videoEnabled && renderer != null
              ? RTCVideoView(
                  key: ObjectKey(renderer),
                  renderer,
                  mirror: mirror,
                  // 拡大中は映像全体を見せる（余白は灰色）、グリッドは枠いっぱい。
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
        ],
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
      OneToOneCallSession(:final controller)
          when !controller.isCaller &&
              controller.state == CallConnectionState.connecting =>
        // 着信中（応答前）: 拒否・応答の2択（2026-09-12追加、call_screen.dartの
        // 全画面着信画面と同じ`CallRoundButton`の組み合わせ。PCでは着信も
        // フルスクリーンを経由しなくなったため、埋め込み表示側にもこの2択を
        // 持たせる必要がある）。
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            CallRoundButton(
              icon: Icons.call_end,
              color: Colors.red,
              isGekiga: isGekiga,
              isGlass: isGlass,
              onPressed: controller.decline,
            ),
            CallRoundButton(
              icon: Icons.call,
              color: Colors.green,
              isGekiga: isGekiga,
              isGlass: isGlass,
              onPressed: !controller.accepting ? controller.accept : null,
            ),
          ],
        ),
      OneToOneCallSession(:final controller) => CallControlBar(
        isGekiga: isGekiga,
        isGlass: isGlass,
        enabled: controller.state == CallConnectionState.active,
        muted: controller.muted,
        onToggleMute: controller.toggleMute,
        speakerOn: controller.speakerOn,
        onToggleSpeaker: controller.toggleSpeaker,
        switchingCallType: controller.switchingCallType,
        onToggleVideoType: cameraAvailability == CameraAvailability.unavailable
            ? null
            : () => controller.setVideoEnabled(!controller.isVideo),
        isVideo: controller.isVideo,
        hasMultipleCameras: controller.hasMultipleCameras,
        switchingCamera: controller.switchingCamera,
        onSwitchCamera: controller.switchCamera,
        onHangUp: controller.hangUp,
      ),
      GroupCallSession(:final controller) => CallControlBar(
        isGekiga: isGekiga,
        isGlass: isGlass,
        enabled: controller.state == GroupCallConnectionState.active,
        muted: controller.muted,
        onToggleMute: controller.toggleMute,
        speakerOn: controller.speakerOn,
        onToggleSpeaker: controller.toggleSpeaker,
        switchingCallType: controller.switchingCallType,
        onToggleVideoType: cameraAvailability == CameraAvailability.unavailable
            ? null
            : () => controller.setVideoEnabled(!controller.isVideo),
        isVideo: controller.isVideo,
        hasMultipleCameras: controller.hasMultipleCameras,
        switchingCamera: controller.switchingCamera,
        onSwitchCamera: controller.switchCamera,
        onHangUp: () => controller.leave(),
      ),
    };
  }
}
