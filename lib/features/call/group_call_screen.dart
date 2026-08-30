import 'dart:math';

import 'package:collection/collection.dart';
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
import 'call_avatar.dart';
import 'call_control_bar.dart';
import 'camera_availability.dart';
import 'webrtc_group_call_controller.dart';

/// 広場（グループ）通話のモバイル向け全画面表示。メッシュ型P2Pのため、
/// 参加者ごとに独立した`RTCVideoRenderer`をグリッド表示する。1対1の
/// [CallScreen]とは異なり、着信（ringing）の概念を持たず「進行中の通話に
/// 途中参加する」形になる。UIも1対1とは意図的に差別化しており、常に
/// グリッド表示から始まり、任意の枠をタップするとその参加者を全画面表示、
/// 全画面表示中に下スワイプするとグリッドに戻る（2026-07-27）。
///
/// 通話コントローラー自体はこの画面ではなく`activeCallSessionProvider`
/// （`active_call_session.dart`）が所有する（2026-08-19変更）。PCでは
/// この画面自体を使わず、メッセージ画面内の埋め込み表示・右上ピン留め
/// ミニ表示を直接使う（広場通話には着信の概念が無いため、1対1と異なり
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

  /// タップでフォーカス（全画面表示）中のタイルのキー。
  /// 自分は`'self'`、相手は`userId`。nullならグリッド表示。
  String? _focusedTileKey;

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
    // （2026-08-19変更、画面を閉じても通話は続くようにするための核と
    // なる変更）。
    super.dispose();
  }

  /// モバイルで下スワイプした時、通話を切らずに右上ピン留めミニ表示へ
  /// ドックする（2026-08-19追加）。フォーカス中タイルの下スワイプ
  /// （グリッドへ戻る操作）とは別物のため、グリッド/音声表示の時だけ
  /// 呼ばれる（build参照）。
  void _dockCall() {
    ref.read(activeCallSessionProvider.notifier).setMinimized(true);
    _popIntentionally();
  }

  /// [CallScreen._popIntentionally]と同じ理由（PopScopeの`canPop`は
  /// 再構築を経て初めて反映されるため）。
  void _popIntentionally() {
    setState(() => _intentionalPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  /// 自分か、現在つながっている参加者の誰か1人でもビデオ通話中なら
  /// ビデオ通話レイアウトを使う（音声⇔ビデオ切替は参加者ごとに独立している
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
        if (!didPop && !_intentionalPop) _controller.leave();
      },
      child: Scaffold(
        backgroundColor: _anyVideo ? colorScheme.surface : displayAreaGrey,
        body: _anyVideo ? _videoBody(displayAreaGrey) : _dockable(_audioBody()),
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

  Widget _audioBody() {
    final remoteParticipants = _controller.remoteParticipants;
    final tiles = <(String userId, String rhingId)>[
      (widget.currentUser.userId, widget.currentUser.rhingId),
      ...remoteParticipants.map((p) => (p.userId, p.rhingId)),
    ];

    return SafeArea(
      child: Column(
        children: [
          // 音声のみの通話でもリモートの音声を再生するためにレンダラーを紐づける。
          SizedBox(
            width: 0,
            height: 0,
            child: Stack(
              children: [
                for (final renderer in _controller.remoteRenderers.values)
                  RTCVideoView(renderer),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '参加者${tiles.length}人',
            style: const TextStyle(color: Colors.white70),
          ),
          const Spacer(),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: [
              for (final (userId, rhingId) in tiles)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CallParticipantAvatar(
                      userId: userId,
                      rhingId: rhingId,
                      conversationId: widget.groupId,
                      radius: 40,
                      fontSize: 28,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '@$rhingId',
                      style: const TextStyle(color: Colors.white),
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
      // まだ他の参加者がいない間も、自分の映像がどう見えているか確認できる
      // ようにフルスクリーンで自分のプレビューを表示する。
      return _dockable(
        SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: _videoTile(
                  userId: widget.currentUser.userId,
                  rhingId: widget.currentUser.rhingId,
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
                    '他の参加者を待っています…',
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

    // 2人以上は人数によらず常にグリッド表示から始め、任意の枠をタップすると
    // その参加者を全画面表示、全画面表示中に下スワイプするとグリッドに
    // 戻る（一対通話の「フルスクリーン＋コーナーPIP」とは意図的に差別化）。
    final entries = <_CallTileEntry>[
      _CallTileEntry(
        key: 'self',
        tile: _videoTile(
          userId: widget.currentUser.userId,
          rhingId: widget.currentUser.rhingId,
          renderer: _controller.isVideo ? _controller.localRenderer : null,
          mirror: _controller.isFrontCamera,
          micMuted: _controller.muted,
          videoEnabled: _controller.isVideo,
          connectionIssue: false,
          placeholderColor: placeholderColor,
        ),
      ),
      for (final participant in remoteParticipants)
        _CallTileEntry(
          key: participant.userId,
          tile: _videoTile(
            userId: participant.userId,
            rhingId: participant.rhingId,
            renderer: _controller.remoteRenderers[participant.userId],
            mirror: false,
            micMuted: participant.micMuted,
            videoEnabled: participant.isVideo,
            connectionIssue:
                _controller.peerConnectionIssues[participant.userId] ?? false,
            placeholderColor: placeholderColor,
          ),
        ),
    ];

    final focused = entries.firstWhereOrNull(
      (entry) => entry.key == _focusedTileKey,
    );

    if (focused != null) {
      // フォーカス中は既存の下スワイプ（グリッドへ戻る）を優先し、ドック用の
      // ジェスチャーは重ねない（同じ縦ドラッグの二重登録を避けるため）。
      return SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onVerticalDragEnd: (details) {
                  if ((details.primaryVelocity ?? 0) > 200) {
                    setState(() => _focusedTileKey = null);
                  }
                },
                child: focused.tile,
              ),
            ),
            const Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white70,
                  size: 28,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(child: _controls()),
            ),
          ],
        ),
      );
    }

    final crossAxisCount = sqrt(tileCount).ceil();

    return _dockable(
      SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: crossAxisCount,
                padding: const EdgeInsets.all(4),
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                children: [
                  for (final entry in entries)
                    GestureDetector(
                      onTap: () => setState(() => _focusedTileKey = entry.key),
                      child: entry.tile,
                    ),
                ],
              ),
            ),
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
    required String rhingId,
    required RTCVideoRenderer? renderer,
    required bool mirror,
    required bool micMuted,
    required bool videoEnabled,
    required bool connectionIssue,
    required Color placeholderColor,
  }) {
    return Container(
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
              key: ObjectKey(renderer),
              renderer,
              mirror: mirror,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            Center(
              child: CallParticipantAvatar(
                userId: userId,
                rhingId: rhingId,
                conversationId: widget.groupId,
                radius: 32,
              ),
            ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Row(
              children: [
                if (micMuted)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.mic_off, size: 14, color: Colors.white),
                  ),
                Text(
                  '@$rhingId',
                  style: const TextStyle(
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 6)],
                  ),
                ),
              ],
            ),
          ),
          if (connectionIssue)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '接続が不安定です',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
            ),
        ],
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
      switchingCallType: _controller.switchingCallType,
      onToggleVideoType: cameraAvailability == CameraAvailability.unavailable
          ? null
          : () => _controller.setVideoEnabled(!_controller.isVideo),
      isVideo: _controller.isVideo,
      hasMultipleCameras: _controller.hasMultipleCameras,
      switchingCamera: _controller.switchingCamera,
      onSwitchCamera: _controller.switchCamera,
      onHangUp: () => _controller.leave(),
    );
  }
}

class _CallTileEntry {
  const _CallTileEntry({required this.key, required this.tile});
  final String key;
  final Widget tile;
}
