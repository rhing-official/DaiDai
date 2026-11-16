import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/app_ui_style.dart';
import '../../models/call.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/camera_availability_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/platform_info.dart';
import 'active_call_session.dart';
import 'call_audio_sinks.dart';
import 'call_avatar.dart';
import 'bgm/call_bgm_bindings.dart';
import 'call_tile_layout.dart';
import 'pip_controller.dart' show enterCallPip;
import 'screen_share.dart' show ScreenShareCapture;
import 'screen_share_menu.dart';
import 'swipe_down_dock.dart';
import 'call_control_bar.dart';
import 'camera_availability.dart';
import 'webrtc_call_controller.dart';
import '../../l10n/strings.dart';

/// 音声・ビデオ通話のモバイル向け全画面表示（発信中・着信中・通話中を
/// 1画面でまとめて扱う）。一対（1対1）限定。開始時点の種別は
/// `call.isVideo`だが、通話中に[WebrtcCallController.setVideoEnabled]で
/// 音声⇔ビデオを切り替えられる（`_controller.isVideo`が自分の現在の種別、
/// `_controller.remoteIsVideo`が相手の現在の種別。切替は互いに独立しており、
/// 相手を強制的に切り替えることは無い）。TURN未導入のためSTUNのみで接続する。
///
/// 通話コントローラー自体はこの画面ではなく`activeCallSessionProvider`
/// （`active_call_session.dart`）が所有する（2026-08-19変更）。この画面は
/// PC埋め込み表示・ピン留めミニ表示が使えないモバイル専用の「全画面ビュー」
/// でしかなく、`initState`で新規生成又は既存セッションへの再アタッチを
/// 行うだけで、`dispose`時にコントローラーを破棄しない（画面を閉じても
/// 通話は続く）。PCでは着信中（応答前）のみこの画面を使い、応答が済み
/// 次第自動的に閉じてメッセージ画面内の埋め込み表示に引き継ぐ
/// （発信側はPCでは最初からこの画面を使わない、`chat_panes.dart`/
/// `talks_tab.dart`の通話開始処理参照）。
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    required this.call,
    required this.isCaller,
    required this.currentUserId,
    super.key,
  });

  final Call call;
  final bool isCaller;
  final String currentUserId;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late final OneToOneCallSession _session;

  /// 映像のある通話だったか（一度でも映像側のレイアウトになったか）。終了の瞬間に映像が破棄されて
  /// 音声通話の画面へ切り替わるのを防ぐための印（2026-11-15）。
  bool _hadVideo = false;

  /// このウィジェット自身の意図したpop（下スワイプでのドック・通話終了後の
  /// 自動クローズ・PCでの応答後の自動クローズ）かどうか。[PopScope]は
  /// `canPop`をpop試行の直前に見る為、これらの意図したpopの前には必ず
  /// `setState`で先にtrueへ更新してから`Navigator.pop`を呼ぶ。falseのまま
  /// のpop試行（システムの戻る操作等）は従来通り切断（hangUp）扱いにする。
  bool _intentionalPop = false;

  /// PCで着信に応答した直後、この全画面ビュー自体を1回だけ自動的に閉じる
  /// （以後はメッセージ画面内の埋め込み表示に任せる）ためのガード。
  bool _autoPoppedForEmbed = false;

  WebrtcCallController get _controller => _session.controller;

  @override
  void initState() {
    super.initState();
    _session = ref
        .read(activeCallSessionProvider.notifier)
        .startOneToOne(
          call: widget.call,
          isCaller: widget.isCaller,
          callRepository: ref.read(callRepositoryProvider),
          directMessageRepository: ref.read(directMessageRepositoryProvider),
        );
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.state == CallConnectionState.ended) {
      // 相手の切断・自分の切断どちらでも、少し見せてから画面を閉じる。映像通話は、
      // 音声通話の画面などが一瞬出ないよう、すぐ閉じる（2026-11-15）。
      Future.delayed(Duration(milliseconds: _hadVideo ? 0 : 400), () {
        if (mounted) _popIntentionally();
      });
      return;
    }
    if (!isMobileCallPlatform &&
        !_autoPoppedForEmbed &&
        _controller.state == CallConnectionState.active) {
      // PCでは、着信への応答が完了した時点でこの全画面ビュー自体は不要に
      // なる（以後はメッセージ画面内の埋め込み表示・右上ピン留めミニ表示が
      // 引き継ぐ）。
      _autoPoppedForEmbed = true;
      _popIntentionally();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    // コントローラー自体は破棄しない。破棄は通話終了（state==ended）を
    // 検知したactiveCallSessionProvider側でのみ行う（2026-08-19変更、
    // 画面を閉じても通話は続くようにする為の核となる変更）。
    super.dispose();
  }

  /// モバイルで下スワイプした時、通話を切らずに右上ピン留めミニ表示へ
  /// ドックする（2026-08-19追加）。
  void _dockCall() {
    ref.read(activeCallSessionProvider.notifier).setMinimized(true);
    _popIntentionally();
  }

  /// `_intentionalPop`をtrueにした上でこの画面をpopする。[PopScope]の
  /// `canPop`はウィジェットの再構築を経て初めて内部の`canPopNotifier`へ
  /// 反映される為、`setState`の直後に同期的に`Navigator.pop`を呼ぶと
  /// 古い`canPop:false`のままpopがブロックされてしまう。次のフレームの
  /// 再構築が終わってから（`addPostFrameCallback`）popすることで、この
  /// 競合を避ける（2026-08-19追加）。
  void _popIntentionally() {
    setState(() => _intentionalPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  String get _otherRhingSeed =>
      widget.call.otherRhingSeed(widget.currentUserId);

  String get _otherUserId => widget.call.otherUserId(widget.currentUserId);

  String get _statusLabel {
    if (_controller.error != null) return _controller.error!;
    final strings = ref.read(appStringsProvider);
    switch (_controller.state) {
      case CallConnectionState.connecting:
        return widget.isCaller
            ? strings.callStatusCalling
            : strings.callStatusConnecting;
      case CallConnectionState.active:
        // 応答済みでも、音声・映像の通り道が確立するまでは届かない（2026-11-16）。
        return _controller.mediaConnected
            ? strings.callStatusActive
            : strings.callStatusEstablishing;
      case CallConnectionState.ended:
        return strings.callStatusEnded;
    }
  }

  /// 通信の確立を待つ間の案内（確立済み・応答前はnull）。長引いたら、入り直しを促す。
  String? get _establishingNotice {
    if (_controller.state != CallConnectionState.active ||
        _controller.mediaConnected) {
      return null;
    }
    final strings = ref.read(appStringsProvider);
    return _controller.establishingTooLong
        ? strings.callEstablishingSlow
        : strings.callEstablishing;
  }

  /// 自分が現在ビデオ通話として動作しているか。
  bool get _myIsVideo => _controller.isVideo;

  /// 相手が現在ビデオ通話として動作しているか。切替は互いに独立している
  /// ため、片方だけがビデオという状態もありうる（その場合、映像が無い側は
  /// プレースホルダー表示になる。_videoBody参照）。
  bool get _remoteIsVideo => _controller.remoteVideoShown;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final anyVideo =
        _myIsVideo ||
        _remoteIsVideo ||
        _controller.remoteScreenShown ||
        _controller.isScreenSharing;
    final ended = _controller.state == CallConnectionState.ended;
    if (anyVideo && !ended) _hadVideo = true;
    // 下スワイプでのドックは、映像がある通話が実際に繋がってから、かつ
    // モバイルでのみ有効にする（音声のみはミニ化しても得るものが無いため
    // 無効、PCはこの全画面ビュー自体を使わないため無効、ユーザー確認済み）。
    // 発信中（呼び出し中）は、映像・音声を問わずミニ表示にできる（2026-11-13追加、
    // 呼び出しを続けたまま他の画面を見たい）。戻る操作もミニ表示になる。
    final dialing =
        isMobileCallPlatform &&
        widget.isCaller &&
        _controller.state == CallConnectionState.connecting;
    final dockEnabled =
        dialing ||
        (isMobileCallPlatform &&
            anyVideo &&
            _controller.state == CallConnectionState.active);

    // 表示領域（映像 or その代役のプレースホルダー）は常に固定のグレー、
    // それ以外（Scaffold自体の背景）は常にテーマの背景色（2026-08-30更新、
    // 「映像表示領域以外は背景色、音声通話の表示領域内は外観に関わらず
    // 灰色」という要望。以前はガラスUIのみ背景色を使っていたが3スタイル
    // 共通にした）。
    final displayAreaGrey = Colors.grey.shade900;

    // 映像通話が終わった瞬間は、音声通話の画面も相手のアイコンも出さず、そのまま閉じる。
    final endedFromVideo = ended && _hadVideo;
    Widget body = endedFromVideo
        ? const Scaffold(backgroundColor: Colors.black)
        : Scaffold(
            backgroundColor: anyVideo ? colorScheme.surface : displayAreaGrey,
            body: _stageBody(colorScheme),
          );
    if (dockEnabled) {
      // 外付けキーボードのEscでも、下スワイプと同じくドックする（2026-10-11追加）。
      body = Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _dockCall();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: body,
      );
      // 下スワイプは生のポインターで判定する（`SwipeDownDock`）。ウィンドウのタップ・ピンの
      // ボタンに負けて効かなくなっていた（beta.7）。
      body = SwipeDownDock(onDock: _dockCall, child: body);
    }

    return PopScope(
      canPop: _intentionalPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _intentionalPop) return;
        // 戻る操作は通話を切らず、OSのPiPに入る（入れない時はアプリ内のミニ表示）。
        // 切るのは終話ボタンだけ。
        _onBack();
      },
      child: body,
    );
  }

  /// 映像が無い側の枠に出す、その人のプロフィールアイコン（2026-10-21変更、
  /// 以前はカメラオフのアイコンで、誰がオフか分かってもアイコンが出なかった）。
  /// [remote]が相手、falseなら自分。
  Widget _placeholderAvatar({required bool remote, required double radius}) {
    final me = widget.currentUserId;
    return CallParticipantAvatar(
      userId: remote ? _otherUserId : me,
      rhingSeed: remote ? _otherRhingSeed : widget.call.myRhingSeed(me),
      conversationId: widget.call.dmId,
      radius: radius,
      fontSize: radius * 0.7,
    );
  }

  /// 戻る操作。AndroidのアプリはOS標準のPiPに入る。入れなければアプリ内のミニ表示にする。
  Future<void> _onBack() async {
    if (await enterCallPip()) return;
    if (mounted) _dockCall();
  }

  /// 1人ぶんのウィンドウ（映像、無ければアイコン。呼び名・ミュート表示つき）。
  Widget _personTile({required bool remote, required bool pinned}) {
    final me = widget.currentUserId;
    final hasVideo = remote ? _remoteIsVideo : _myIsVideo;
    final renderer = remote
        ? _controller.remoteRenderer
        : _controller.localRenderer;
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCallTileRadius),
      child: Container(
        color: Colors.grey.shade900,
        child: Stack(
          fit: StackFit.expand,
          children: [
            hasVideo
                ? CallPersonVideo(
                    renderer: renderer,
                    mirror: !remote && _controller.isFrontCamera,
                    fullFit: pinned,
                  )
                : Center(
                    child: _placeholderAvatar(
                      remote: remote,
                      radius: pinned ? 56 : 28,
                    ),
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
                        userId: remote ? _otherUserId : me,
                        rhingSeed: remote
                            ? _otherRhingSeed
                            : widget.call.myRhingSeed(me),
                        conversationId: widget.call.dmId,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      CallMicStatus(
                        muted: remote
                            ? _controller.remoteMuted
                            : _controller.muted,
                        unavailable: remote
                            ? _controller.remoteMicUnavailable
                            : _controller.micUnavailable,
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

  /// 画面共有のウィンドウ（共有の画面。ライブ・画質つき）。
  Widget _screenTile({required bool remote}) {
    final strings = ref.watch(appStringsProvider);
    final me = widget.currentUserId;
    final renderer = remote
        ? _controller.remoteScreenRenderer
        : _controller.localScreenRenderer;
    return ScreenShareFrame(
      video: (!remote && ScreenShareCapture.isNativeAndroid)
          ? ScreenSharePreview(
              trackOf: () => _controller.screenVideoTrack,
              liveRenderer: _controller.localScreenRenderer,
            )
          : (remote && !_controller.remoteScreenReady)
          ? ScreenReceivingView(failed: _controller.remoteScreenTimedOut)
          : CallZoomRegion(
              renderer: renderer,
              contain: true,
              child: RTCVideoView(
                key: ValueKey(renderer),
                renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              ),
            ),
      name: CallParticipantNameLabel(
        userId: remote ? _otherUserId : me,
        rhingSeed: remote ? _otherRhingSeed : widget.call.myRhingSeed(me),
        conversationId: widget.call.dmId,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      qualityLabel: remote
          ? (_controller.remoteScreenLabel ?? '')
          : _controller.screenQuality.label,
      liveText: strings.callScreenShareLive,
      notice: (!remote && _controller.screenDeliveryFailed)
          ? ScreenDeliveryNotice(onRetry: _controller.resendScreenShare)
          : null,
    );
  }

  /// 画面の上に重ねる、小さな案内（状態・通信の確立・接続の不安定）。
  Widget _banner(String text, {Key? key}) => Center(
    key: key,
    child: Container(
      margin: const EdgeInsets.only(top: 8, left: 12, right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    ),
  );

  /// 通話の本体（2026-11-16）。ウィンドウ（共有は1枚と数えて最上行・自分・相手）を、広場と同じ
  /// 並べ方・ピン留めで出す（音声通話・ビデオ通話・画面共有で共通）。
  Widget _stageBody(ColorScheme colorScheme) {
    final isActive = _controller.state == CallConnectionState.active;
    final specs = [
      if (_controller.remoteScreenShown)
        CallTileSpec(
          key: 'remote#screen',
          volume: CallTileVolume(
            value: _controller.remoteScreenVolume,
            onChanged: _controller.setRemoteScreenVolume,
          ),
          build: (_) => _screenTile(remote: true),
        ),
      if (_controller.isScreenSharing)
        CallTileSpec(
          key: 'self#screen',
          build: (_) => _screenTile(remote: false),
        ),
      CallTileSpec(
        key: 'self',
        build: (pinned) => _personTile(remote: false, pinned: pinned),
      ),
      CallTileSpec(
        key: 'remote',
        volume: CallTileVolume(
          value: _controller.remoteVoiceVolume,
          onChanged: _controller.setRemoteVoiceVolume,
        ),
        build: (pinned) => _personTile(remote: true, pinned: pinned),
      ),
    ];
    // 通話が確立するまでは状態（呼び出し中・接続中）を、確立後も届くまでの間は案内を出す。
    final status =
        !isActive || _controller.error != null || !_controller.mediaConnected
        ? _statusLabel
        : null;
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              // 相手の映像のウィンドウが無い間も、相手の音声を鳴らす（2026-10-31追加）。
              CallAudioSinks(
                renderers: _remoteIsVideo ? [] : [_controller.remoteRenderer],
              ),
              Expanded(child: CallTileStage(specs: specs)),
              Padding(
                padding: const EdgeInsets.only(bottom: 24, top: 8),
                child: _controls(colorScheme),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Column(
                children: [
                  if (status != null)
                    _banner(status, key: const ValueKey('call-status')),
                  if (_establishingNotice != null)
                    _banner(
                      _establishingNotice!,
                      key: const ValueKey('connection-establishing'),
                    ),
                  if (isActive && _controller.connectionIssue)
                    _banner(
                      ref
                          .read(appStringsProvider)
                          .callConnectionUnstableEllipsis,
                      key: const ValueKey('connection-issue'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(ColorScheme colorScheme) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;

    final isActive = _controller.state == CallConnectionState.active;
    final cameraAvailability =
        ref.watch(cameraAvailabilityProvider).value ??
        CameraAvailability.unknown;
    return CallControlBar(
      isGekiga: isGekiga,
      isGlass: isGlass,
      enabled: isActive,
      muted: _controller.muted,
      onToggleMute: _controller.toggleMute,
      speakerOn: _controller.speakerOn,
      onToggleSpeaker: _controller.toggleSpeaker,
      showSpeakerToggle: _controller.showSpeakerToggle,
      switchingCallType: _controller.switchingCallType,
      onToggleVideoType: cameraAvailability == CameraAvailability.unavailable
          ? null
          : () => _controller.setVideoEnabled(!_myIsVideo),
      isVideo: _myIsVideo,
      hasMultipleCameras: _controller.hasMultipleCameras,
      switchingCamera: _controller.switchingCamera,
      onSwitchCamera: _controller.switchCamera,
      onHangUp: _controller.hangUp,
      bgmBinding: oneToOneBgmBinding(_controller),
      soundboardBinding: oneToOneSoundboardBinding(
        _controller,
        widget.currentUserId,
      ),
      screenShare: oneToOneScreenShare(_controller, widget.currentUserId),
      remoteBgm: _controller.remoteBgm,
      videoFailed: _controller.videoFailed,
      micUnavailable: _controller.micUnavailable,
      micBusyAtJoin: _controller.micBusyAtJoin,
    );
  }
}
