import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/camera_availability_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/platform_info.dart';
import '../../widgets/swipe_gestures.dart' show kSwipeGestureVelocityThreshold;
import 'active_call_session.dart';
import 'call_audio_sinks.dart';
import 'call_avatar.dart';
import '../../providers/call_bgm_provider.dart';
import 'bgm/call_bgm_bindings.dart';
import 'screen_share_menu.dart';
import 'call_control_bar.dart';
import 'call_tile_layout.dart';
import 'call_video_viewer.dart';
import 'camera_availability.dart';
import 'webrtc_group_call_controller.dart';
import '../../l10n/strings.dart';

/// 広場（グループ）通話のモバイル向け全画面表示。メッシュ型P2Pの為、
/// 参加者毎に独立した`RTCVideoRenderer`をグリッド表示する。1対1の
/// [CallScreen]とは異なり、着信（ringing）の概念を持たず「進行中の通話に
/// 途中参加する」形になる。UIも1対1とは意図的に差別化しており、常に
/// グリッド表示から始まり、任意の枠をタップするとその参加者を全画面表示、
/// 全画面表示中に下スワイプするとグリッドに戻る（2026-07-27）。
///
/// 通話コントローラー自体はこの画面ではなく`activeCallSessionProvider`
/// （`active_call_session.dart`）が所有する（2026-08-19変更）。PCでは
/// この画面自体を使わず、メッセージ画面内の埋め込み表示・右上ピン留め
/// ミニ表示を直接使う（広場通話には着信の概念が無い為、1対1と異なり
/// PCでもこの全画面ビューを経由する場面自体が無い）。
class GroupCallScreen extends ConsumerStatefulWidget {
  const GroupCallScreen({
    required this.groupCallId,
    required this.groupId,
    required this.currentUser,
    required this.isVideo,
    super.key,
  });

  final String groupCallId;
  final String groupId;
  final AppUser currentUser;
  final bool isVideo;

  @override
  ConsumerState<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends ConsumerState<GroupCallScreen> {
  late final GroupCallSession _session;

  /// 拡大表示（映像のビューア）を閉じるたびに増やし、映像の部品を作り直す
  /// （Webの描画要素は拡大側へ移る為）。
  int _viewerGeneration = 0;

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

  /// このウィジェット自身の意図したpop（下スワイプでのドック・通話終了後の
  /// 自動クローズ）かどうか。詳細は[CallScreen]の同名フィールドのコメント
  /// 参照（同じ理由でPopScopeとの競合を避けるため必要）。
  bool _intentionalPop = false;

  WebrtcGroupCallController get _controller => _session.controller;

  @override
  void initState() {
    super.initState();
    _session = ref
        .read(activeCallSessionProvider.notifier)
        .startGroup(
          groupCallId: widget.groupCallId,
          groupId: widget.groupId,
          currentUser: widget.currentUser,
          isVideo: widget.isVideo,
          groupCallRepository: ref.read(groupCallRepositoryProvider),
        );
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.state == GroupCallConnectionState.ended) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _popIntentionally();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    // コントローラー自体は破棄・退出処理をしない。破棄は通話終了
    // （state==ended）を検知したactiveCallSessionProvider側でのみ行う
    // （2026-08-19変更、画面を閉じても通話は続くようにする為の核と
    // なる変更）。
    super.dispose();
  }

  /// モバイルで下スワイプした時、通話を切らずに右上ピン留めミニ表示へ
  /// ドックする（2026-08-19追加）。フォーカス中タイルの下スワイプ
  /// （グリッドへ戻る操作）とは別物の為、グリッド/音声表示の時だけ
  /// 呼ばれる（build参照）。
  void _dockCall() {
    ref.read(activeCallSessionProvider.notifier).setMinimized(true);
    _popIntentionally();
  }

  /// [CallScreen._popIntentionally]と同じ理由（PopScopeの`canPop`は
  /// 再構築を経て初めて反映される為）。
  void _popIntentionally() {
    setState(() => _intentionalPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  /// 自分か、現在つながっている参加者の誰か1人でもビデオ通話中なら
  /// ビデオ通話レイアウトを使う（音声⇔ビデオ切替は参加者毎に独立している
  /// ため、全員が同じ種別とは限らない）。
  bool get _anyVideo =>
      _controller.isVideo ||
      _controller.remoteParticipants.any((p) => p.isVideo);

  @override
  Widget build(BuildContext context) {
    // 表示領域（映像 or その代役のプレースホルダー）は常に固定のグレー、
    // それ以外（Scaffold自体の背景）は常にテーマの背景色（2026-08-30更新、
    // 「映像表示領域以外は背景色、音声通話の表示領域内は外観に関わらず
    // 灰色」という要望。以前はガラスUIのみ背景色を使っていたが3スタイル
    // 共通にした）。
    final colorScheme = Theme.of(context).colorScheme;
    final displayAreaGrey = Colors.grey.shade900;
    return PopScope(
      canPop: _intentionalPop,
      onPopInvokedWithResult: (didPop, _) {
        // 戻る操作は退出せず、ミニ表示にする（退出は終話ボタンだけ）。
        if (!didPop && !_intentionalPop) _dockCall();
      },
      child: Scaffold(
        backgroundColor: _anyVideo ? colorScheme.surface : displayAreaGrey,
        body: _anyVideo
            ? Stack(
                children: [
                  Positioned.fill(child: _videoBody(displayAreaGrey)),
                  if (_waitingForPeers) _establishingBanner(),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: CallAudioSinks(
                      renderers: _undisplayedRemoteRenderers(),
                    ),
                  ),
                ],
              )
            : _dockable(_audioBody()),
      ),
    );
  }

  /// 参加済みなのに、他の参加者の誰ともまだ通信が確立していない（確立まで数秒かかる、2026-11-16）。
  bool get _waitingForPeers {
    if (_controller.state != GroupCallConnectionState.active) return false;
    final remotes = _controller.remoteParticipants;
    return remotes.isNotEmpty &&
        remotes.every((p) => !_controller.isPeerEstablished(p.userId));
  }

  /// 上部に出す、通信の確立待ちの案内。
  Widget _establishingBanner() {
    return Positioned(
      key: const ValueKey('connection-establishing'),
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.only(top: 8, left: 12, right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              ref.read(appStringsProvider).callEstablishingGroup,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }

  /// モバイルで下スワイプした時にドックする（2026-08-19追加）。音声のみの
  /// 通話ではミニ化しても得るものが無いため無効、PCはこの全画面ビュー自体を
  /// 使わないため無効（ユーザー確認済み）。フォーカス中タイル表示は独自の
  /// 下スワイプ（グリッドへ戻る）を持つため対象外にする（呼び出し元参照）。
  Widget _dockable(Widget child) {
    final dockEnabled =
        isMobileCallPlatform &&
        _anyVideo &&
        _controller.state == GroupCallConnectionState.active;
    if (!dockEnabled) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity >= kSwipeGestureVelocityThreshold) _dockCall();
      },
      child: child,
    );
  }

  /// 映像を画面に出していない参加者のレンダラー（音声だけ鳴らす、2026-10-21、映像オフの
  /// 参加者の音声が聞こえなかった不具合の修正）。
  List<RTCVideoRenderer> _undisplayedRemoteRenderers() {
    final remotes = _controller.remoteParticipants;
    final ids = groupAudioOnlyUserIds(
      remoteIds: [for (final p in remotes) p.userId],
      videoOnIds: {
        for (final p in remotes)
          if (_controller.remoteVideoShown(p)) p.userId,
      },
    );
    return [
      for (final id in ids)
        if (_controller.remoteRenderers[id] != null)
          _controller.remoteRenderers[id]!,
    ];
  }

  Widget _audioBody() {
    final remoteParticipants = _controller.remoteParticipants;
    final tiles = <(String userId, String rhingSeed)>[
      (widget.currentUser.userId, widget.currentUser.rhingSeed),
      ...remoteParticipants.map((p) => (p.userId, p.rhingSeed)),
    ];

    return SafeArea(
      child: Column(
        children: [
          // 音声のみの通話でもリモートの音声を再生する為にレンダラーを紐づける
          // （0×0だとモバイルのブラウザが再生しないことがある為、1×1・ほぼ
          // 透明の[CallAudioSinks]にした、2026-10-21）。
          CallAudioSinks(
            renderers: _controller.remoteRenderers.values.toList(),
          ),
          const SizedBox(height: 24),
          Text(
            ref
                .read(appStringsProvider)
                .groupCallParticipantCountTemplate(tiles.length),
            style: const TextStyle(color: Colors.white70),
          ),
          if (_waitingForPeers)
            Padding(
              key: const ValueKey('connection-establishing'),
              padding: const EdgeInsets.only(top: 8, left: 24, right: 24),
              child: Text(
                ref.read(appStringsProvider).callEstablishingGroup,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          const Spacer(),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: [
              for (final (userId, rhingSeed) in tiles)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CallParticipantAvatar(
                      userId: userId,
                      rhingSeed: rhingSeed,
                      conversationId: widget.groupId,
                      radius: 40,
                      fontSize: 28,
                    ),
                    const SizedBox(height: 8),
                    CallParticipantNameLabel(
                      userId: userId,
                      rhingSeed: rhingSeed,
                      conversationId: widget.groupId,
                      style: const TextStyle(color: Colors.white),
                    ),
                    if (userId != widget.currentUser.userId &&
                        _controller.state == GroupCallConnectionState.active &&
                        !_controller.isPeerEstablished(userId))
                      Text(
                        ref.read(appStringsProvider).callPeerConnecting,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
            ],
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 48),
            child: _controls(),
          ),
        ],
      ),
    );
  }

  Widget _videoBody(Color placeholderColor) {
    final remoteParticipants = _controller.remoteParticipants;
    final tileCount = 1 + remoteParticipants.length;

    if (tileCount == 1) {
      // まだ他の参加者がいない間も、自分の映像がどう見えているか確認出来る
      // ようにフルスクリーンで自分のプレビューを表示する。
      return _dockable(
        SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: _videoTile(
                  userId: widget.currentUser.userId,
                  rhingSeed: widget.currentUser.rhingSeed,
                  renderer: _controller.isVideo
                      ? _controller.localRenderer
                      : null,
                  mirror: _controller.isFrontCamera,
                  micMuted: _controller.muted,
                  videoEnabled: _controller.isVideo,
                  connectionIssue: false,
                  placeholderColor: placeholderColor,
                ),
              ),
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    ref.read(appStringsProvider).groupCallWaitingForOthers,
                    style: const TextStyle(
                      color: Colors.white70,
                      shadows: [Shadow(blurRadius: 6)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(child: _controls()),
              ),
            ],
          ),
        ),
      );
    }

    // 2人以上は、一対と同じ並べ方（`CallTileStage`、画面共有も1枚と数えて最上行、
    // ピン留め可、2026-11-16）。タップは映像の拡大ビューア。
    final strings = ref.watch(appStringsProvider);
    CallTileSpec screenSpec({
      required String userId,
      required String rhingSeed,
      required RTCVideoRenderer renderer,
      required String label,
    }) => CallTileSpec(
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
          conversationId: widget.groupId,
          style: const TextStyle(
            color: Colors.white,
            shadows: [Shadow(blurRadius: 6)],
          ),
        ),
        qualityLabel: label,
        liveText: strings.callScreenShareLive,
      ),
    );

    CallTileSpec personSpec({
      required String userId,
      required String rhingSeed,
      required RTCVideoRenderer? renderer,
      required bool mirror,
      required bool micMuted,
      required bool videoEnabled,
      required bool connectionIssue,
      bool connecting = false,
    }) => CallTileSpec(
      key: userId,
      onTap: videoEnabled && renderer != null
          ? () => _openViewer(renderer, mirror: mirror)
          : null,
      build: (_) => _videoTile(
        userId: userId,
        rhingSeed: rhingSeed,
        renderer: renderer,
        mirror: mirror,
        micMuted: micMuted,
        videoEnabled: videoEnabled,
        connectionIssue: connectionIssue,
        connecting: connecting,
        placeholderColor: placeholderColor,
      ),
    );

    final specs = <CallTileSpec>[
      if (_controller.isScreenSharing)
        screenSpec(
          userId: widget.currentUser.userId,
          rhingSeed: widget.currentUser.rhingSeed,
          renderer: _controller.localScreenRenderer,
          label: _controller.screenQuality.label,
        ),
      for (final participant in remoteParticipants)
        if (_controller.remoteScreenShown(participant))
          screenSpec(
            userId: participant.userId,
            rhingSeed: participant.rhingSeed,
            renderer: _controller.screenRenderers[participant.userId]!,
            label: participant.screenLabel ?? '',
          ),
      personSpec(
        userId: widget.currentUser.userId,
        rhingSeed: widget.currentUser.rhingSeed,
        renderer: _controller.isVideo ? _controller.localRenderer : null,
        mirror: _controller.isFrontCamera,
        micMuted: _controller.muted,
        videoEnabled: _controller.isVideo,
        connectionIssue: false,
      ),
      for (final participant in remoteParticipants)
        personSpec(
          userId: participant.userId,
          rhingSeed: participant.rhingSeed,
          renderer: _controller.remoteRenderers[participant.userId],
          mirror: false,
          micMuted: participant.micMuted,
          videoEnabled: _controller.remoteVideoShown(participant),
          connectionIssue:
              _controller.peerConnectionIssues[participant.userId] ?? false,
          connecting:
              _controller.state == GroupCallConnectionState.active &&
              !_controller.isPeerEstablished(participant.userId),
        ),
    ];

    return _dockable(
      SafeArea(
        child: Column(
          children: [
            Expanded(child: CallTileStage(specs: specs)),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _controls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoTile({
    required String userId,
    required String rhingSeed,
    required RTCVideoRenderer? renderer,
    required bool mirror,
    required bool micMuted,
    required bool videoEnabled,
    required bool connectionIssue,
    bool connecting = false,
    required Color placeholderColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCallTileRadius),
      child: Container(
        color: placeholderColor,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (videoEnabled && renderer != null)
              RTCVideoView(
                // Web版のRTCVideoViewはStatefulWidgetで、実描画に使う
                // videoElementをinitState時にしか取得しない。2人通話の
                // メイン/コーナー入れ替え時、keyが無いとFlutterが同じ
                // Stateを使い回してしまい映像が入れ替わらない不具合になって
                // いた。レンダラーの実体が変わったら必ず作り直されるよう、
                // レンダラー自体をキーにする。
                key: ValueKey((renderer, _viewerGeneration)),
                renderer,
                mirror: mirror,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              Center(
                child: CallParticipantAvatar(
                  userId: userId,
                  rhingSeed: rhingSeed,
                  conversationId: widget.groupId,
                  radius: 32,
                ),
              ),
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
                      conversationId: widget.groupId,
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
            if (_controller.speakingUserIds.contains(userId))
              Positioned.fill(child: SpeakingFrame()),
            if (connectionIssue || connecting)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    connectionIssue
                        ? ref.read(appStringsProvider).callConnectionUnstable
                        : ref.read(appStringsProvider).callPeerConnecting,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final isActive = _controller.state == GroupCallConnectionState.active;
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
          : () => _controller.setVideoEnabled(!_controller.isVideo),
      isVideo: _controller.isVideo,
      hasMultipleCameras: _controller.hasMultipleCameras,
      switchingCamera: _controller.switchingCamera,
      onSwitchCamera: _controller.switchCamera,
      onHangUp: () => _controller.leave(),
      videoFailed: _controller.videoFailed,
      remoteBgm: _controller.remoteBgm,
      screenShare: groupScreenShare(_controller),
      bgmBinding: groupBgmBinding(
        _controller,
        allowed: ref.watch(
          canPlayCallBgmProvider((
            groupId: widget.groupId,
            userId: _controller.currentUser.userId,
          )),
        ),
      ),
    );
  }
}
