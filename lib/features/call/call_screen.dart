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
import '../../widgets/swipe_gestures.dart' show kSwipeGestureVelocityThreshold;
import 'active_call_session.dart';
import 'call_avatar.dart';
import 'call_control_bar.dart';
import 'call_controls.dart';
import 'camera_availability.dart';
import 'webrtc_call_controller.dart';

/// 音声・ビデオ通話のモバイル向け全画面表示（発信中・着信中・通話中を
/// 1画面でまとめて扱う）。一対（1対1）限定。開始時点の種別は
/// `call.isVideo`だが、通話中に[WebrtcCallController.setVideoEnabled]で
/// 音声⇔ビデオを切り替えられる（`_controller.isVideo`が自分の現在の種別、
/// `_controller.remoteIsVideo`が相手の現在の種別。切替は互いに独立しており、
/// 相手を強制的に切り替えることはない）。TURN未導入のためSTUNのみで接続する。
///
/// 通話コントローラー自体はこの画面ではなく`activeCallSessionProvider`
/// （`active_call_session.dart`）が所有する（2026-08-19変更）。この画面は
/// PC埋め込み表示・ピン留めミニ表示が使えないモバイル専用の「全画面ビュー」
/// でしかなく、`initState`で新規生成または既存セッションへの再アタッチを
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

  /// ビデオ通話でフルスクリーン側に相手（true）/自分（false）どちらを
  /// 表示するか。タップで入れ替える。
  bool _mainViewIsRemote = true;

  /// このウィジェット自身の意図したpop（下スワイプでのドック・通話終了後の
  /// 自動クローズ・PCでの応答後の自動クローズ）かどうか。[PopScope]は
  /// `canPop`をpop試行の直前に見るため、これらの意図したpopの前には必ず
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
      // 相手の切断・自分の切断どちらでも、少し見せてから画面を閉じる。
      Future.delayed(const Duration(milliseconds: 400), () {
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
    // 画面を閉じても通話は続くようにするための核となる変更）。
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
  /// 反映されるため、`setState`の直後に同期的に`Navigator.pop`を呼ぶと
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

  String get _otherRhingId => widget.call.otherRhingId(widget.currentUserId);

  String get _otherUserId => widget.call.otherUserId(widget.currentUserId);

  String get _statusLabel {
    if (_controller.error != null) return _controller.error!;
    switch (_controller.state) {
      case CallConnectionState.connecting:
        return widget.isCaller ? '発信中…' : '接続中…';
      case CallConnectionState.active:
        return '通話中';
      case CallConnectionState.ended:
        return '通話終了';
    }
  }

  /// 自分が現在ビデオ通話として動作しているか。
  bool get _myIsVideo => _controller.isVideo;

  /// 相手が現在ビデオ通話として動作しているか。切替は互いに独立している
  /// ため、片方だけがビデオという状態もありうる（その場合、映像が無い側は
  /// プレースホルダー表示になる。_videoBody参照）。
  bool get _remoteIsVideo => _controller.remoteIsVideo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final anyVideo = _myIsVideo || _remoteIsVideo;
    // 下スワイプでのドックは、映像がある通話が実際に繋がってから、かつ
    // モバイルでのみ有効にする（音声のみはミニ化しても得るものが無いため
    // 無効、PCはこの全画面ビュー自体を使わないため無効、ユーザー確認済み）。
    final dockEnabled =
        isMobileCallPlatform &&
        anyVideo &&
        _controller.state == CallConnectionState.active;

    // 表示領域（映像 or その代役のプレースホルダー）は常に固定のグレー、
    // それ以外（Scaffold自体の背景）は常にテーマの背景色（2026-08-30更新、
    // 「映像表示領域以外は背景色、音声通話の表示領域内は外観に関わらず
    // 灰色」という要望。以前はガラスUIのみ背景色を使っていたが3スタイル
    // 共通にした）。
    final displayAreaGrey = Colors.grey.shade900;

    Widget body = Scaffold(
      backgroundColor: anyVideo ? colorScheme.surface : displayAreaGrey,
      body: anyVideo
          ? _videoBody(colorScheme, displayAreaGrey)
          : _audioBody(colorScheme),
    );
    if (dockEnabled) {
      body = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity >= kSwipeGestureVelocityThreshold) _dockCall();
        },
        child: body,
      );
    }

    return PopScope(
      canPop: _intentionalPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_intentionalPop) _controller.hangUp();
      },
      child: body,
    );
  }

  Widget _audioBody(ColorScheme colorScheme) {
    return SafeArea(
      child: Column(
        children: [
          // 音声のみの通話でもリモートの音声を再生するためにレンダラーを紐づける。
          SizedBox(
            width: 0,
            height: 0,
            child: RTCVideoView(_controller.remoteRenderer),
          ),
          const Spacer(),
          CallParticipantAvatar(
            userId: _otherUserId,
            rhingId: _otherRhingId,
            conversationId: widget.call.dmId,
            radius: 56,
            fontSize: 40,
          ),
          const SizedBox(height: 24),
          CallParticipantNameLabel(
            userId: _otherUserId,
            rhingId: _otherRhingId,
            conversationId: widget.call.dmId,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(_statusLabel, style: const TextStyle(color: Colors.white70)),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 48),
            child: _controls(colorScheme),
          ),
        ],
      ),
    );
  }

  /// ビデオ通話のレイアウト。相手の映像を画面全面に敷き、上部に名前・状態、
  /// 右上に自分のカメラプレビューを重ねる。相手の映像がまだ届いていない
  /// （発信中・接続中）の間は背景が黒いだけになるため、中央にアバターを重ねて
  /// 音声通話と同じように相手が誰かを常に視認できるようにする。
  Widget _videoBody(ColorScheme colorScheme, Color placeholderColor) {
    final isConnected = _controller.state == CallConnectionState.active;
    final mainRenderer = _mainViewIsRemote
        ? _controller.remoteRenderer
        : _controller.localRenderer;
    final pipRenderer = _mainViewIsRemote
        ? _controller.localRenderer
        : _controller.remoteRenderer;

    // 音声⇔ビデオの切替は自分・相手それぞれ独立しているため、映像が無い側
    // （自分が音声のみ、または相手が音声のみ）はプレースホルダーで表示する。
    final mainShowsPlaceholder = _mainViewIsRemote
        ? !_remoteIsVideo
        : !_myIsVideo;
    final pipShowsPlaceholder = _mainViewIsRemote
        ? !_myIsVideo
        : !_remoteIsVideo;

    void swapViews() => setState(() => _mainViewIsRemote = !_mainViewIsRemote);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: swapViews,
            child: mainShowsPlaceholder
                ? Container(
                    color: placeholderColor,
                    child: const Center(
                      child: Icon(
                        Icons.videocam_off,
                        color: Colors.white54,
                        size: 48,
                      ),
                    ),
                  )
                : RTCVideoView(
                    // Web版のRTCVideoViewはStatefulWidgetで、実描画に使う
                    // videoElementをinitState時にしか取得しない。keyが無いと
                    // メイン/コーナーを入れ替えてもFlutterが同じStateを使い
                    // 回してしまい、映像が入れ替わらずミラー表示だけが
                    // 切り替わって見える不具合になっていた。レンダラーの
                    // 実体が変わったら必ず作り直されるよう、レンダラー自体を
                    // キーにする。
                    key: ObjectKey(mainRenderer),
                    mainRenderer,
                    mirror: !_mainViewIsRemote && _controller.isFrontCamera,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
          ),
        ),
        if (!isConnected)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CallParticipantAvatar(
                  userId: _otherUserId,
                  rhingId: _otherRhingId,
                  conversationId: widget.call.dmId,
                  radius: 56,
                  fontSize: 40,
                ),
                const SizedBox(height: 16),
                CallParticipantNameLabel(
                  userId: _otherUserId,
                  rhingId: _otherRhingId,
                  conversationId: widget.call.dmId,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        if (isConnected && _controller.connectionIssue)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '接続が不安定です…',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CallParticipantNameLabel(
                            userId: _otherUserId,
                            rhingId: _otherRhingId,
                            conversationId: widget.call.dmId,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [Shadow(blurRadius: 6)],
                            ),
                          ),
                          Text(
                            _statusLabel,
                            style: const TextStyle(
                              color: Colors.white70,
                              shadows: [Shadow(blurRadius: 6)],
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: swapViews,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 90,
                          height: 130,
                          color: placeholderColor,
                          child: pipShowsPlaceholder
                              ? const Icon(
                                  Icons.videocam_off,
                                  color: Colors.white54,
                                )
                              : RTCVideoView(
                                  key: ObjectKey(pipRenderer),
                                  pipRenderer,
                                  mirror:
                                      _mainViewIsRemote &&
                                      _controller.isFrontCamera,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _controls(colorScheme),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controls(ColorScheme colorScheme) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final isRinging = _controller.state == CallConnectionState.connecting;

    if (isRinging && !widget.isCaller) {
      // 着信中: 拒否・応答の2択。
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          CallRoundButton(
            icon: Icons.call_end,
            color: Colors.red,
            isGekiga: isGekiga,
            isGlass: isGlass,
            onPressed: _controller.decline,
          ),
          CallRoundButton(
            icon: Icons.call,
            color: Colors.green,
            isGekiga: isGekiga,
            isGlass: isGlass,
            onPressed: !_controller.accepting
                ? () {
                    HapticFeedback.vibrate();
                    _controller.accept();
                  }
                : null,
          ),
        ],
      );
    }

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
      switchingCallType: _controller.switchingCallType,
      onToggleVideoType: cameraAvailability == CameraAvailability.unavailable
          ? null
          : () => _controller.setVideoEnabled(!_myIsVideo),
      isVideo: _myIsVideo,
      hasMultipleCameras: _controller.hasMultipleCameras,
      switchingCamera: _controller.switchingCamera,
      onSwitchCamera: _controller.switchCamera,
      onHangUp: _controller.hangUp,
    );
  }
}
