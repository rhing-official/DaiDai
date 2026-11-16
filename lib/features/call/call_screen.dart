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
import 'call_audio_sinks.dart';
import 'call_avatar.dart';
import 'bgm/call_bgm_bindings.dart';
import 'call_tile_layout.dart';
import 'screen_share_menu.dart';
import 'call_control_bar.dart';
import 'call_video_viewer.dart';
import 'call_tile_layout.dart' show callVideoFitFor;
import 'camera_availability.dart';
import 'pinned_call_position.dart' show clampPinnedCallOffset;
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

  /// ビデオ通話でフルスクリーン側に相手（true）/自分（false）どちらを
  /// 表示するか。タップで入れ替える。
  bool _mainViewIsRemote = true;

  /// 拡大表示を閉じるたびに増やし、映像の部品を作り直す（`call_overlay.dart`と同じ）。
  int _viewerGeneration = 0;

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
        _myIsVideo || _remoteIsVideo || _controller.remoteScreenShown;
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
            body: _controller.remoteScreenShown
                ? _screenBody(colorScheme)
                : anyVideo
                ? _videoBody(colorScheme, displayAreaGrey)
                : _audioBody(colorScheme),
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
        if (didPop || _intentionalPop) return;
        // 戻る操作は通話を切らず、ミニ表示にする（切るのは終話ボタンだけ）。
        _dockCall();
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

  /// 拡大している画面共有のグリッドのタイル（`screen`・`remote`・`self`。nullならグリッド）。
  String? _focusedScreenKey;

  /// 相手が画面共有している時の表示（2026-11-15）。共有の画面を、Discordのように、相手・自分の
  /// タイルと同じグリッド（縦長なので縦に積む）の1つとして出す。タップで拡大・もう一度で戻る。
  Widget _screenBody(ColorScheme colorScheme) {
    final strings = ref.watch(appStringsProvider);
    final keys = ['screen', 'self', 'remote'];
    final focused = keys.contains(_focusedScreenKey) ? _focusedScreenKey : null;

    Widget person({required bool remote}) {
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
                  ? RTCVideoView(
                      key: ObjectKey(renderer),
                      renderer,
                      mirror: !remote && _controller.isFrontCamera,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Center(
                      child: _placeholderAvatar(remote: remote, radius: 28),
                    ),
              Positioned(
                left: 8,
                bottom: 8,
                child: CallLabelSheet(
                  child: CallParticipantNameLabel(
                    userId: remote ? _otherUserId : widget.currentUserId,
                    rhingSeed: remote
                        ? _otherRhingSeed
                        : widget.call.myRhingSeed(widget.currentUserId),
                    conversationId: widget.call.dmId,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget tileFor(String key) {
      final renderer = _controller.remoteScreenRenderer;
      final tile = switch (key) {
        'screen' => ScreenShareFrame(
          video: RTCVideoView(
            key: ObjectKey(renderer),
            renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          ),
          name: CallParticipantNameLabel(
            userId: _otherUserId,
            rhingSeed: _otherRhingSeed,
            conversationId: widget.call.dmId,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          qualityLabel: _controller.remoteScreenLabel ?? '',
          liveText: strings.callScreenShareLive,
        ),
        'remote' => person(remote: true),
        _ => person(remote: false),
      };
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            setState(() => _focusedScreenKey = focused == key ? null : key),
        child: tile,
      );
    }

    return SafeArea(
      child: Column(
        children: [
          CallAudioSinks(
            renderers:
                (_remoteIsVideo && (focused == null || focused == 'remote'))
                ? const []
                : [_controller.remoteRenderer],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: focused != null
                  ? tileFor(focused)
                  : CallTileColumn(tiles: [for (final k in keys) tileFor(k)]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 24, top: 8),
            child: _controls(colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _audioBody(ColorScheme colorScheme) {
    return SafeArea(
      child: Column(
        children: [
          // 音声のみの通話でもリモートの音声を再生する為にレンダラーを紐づける
          // （0×0だとモバイルのブラウザが再生しないことがある為、1×1の
          // `CallAudioSinks`にした。2026-10-31変更）。
          CallAudioSinks(renderers: [_controller.remoteRenderer]),
          const Spacer(),
          CallParticipantAvatar(
            userId: _otherUserId,
            rhingSeed: _otherRhingSeed,
            conversationId: widget.call.dmId,
            radius: 56,
            fontSize: 40,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CallParticipantNameLabel(
                userId: _otherUserId,
                rhingSeed: _otherRhingSeed,
                conversationId: widget.call.dmId,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              // 相手のミュート表示（2026-10-31追加）。
              if (_controller.remoteMuted)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.mic_off, color: Colors.white),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_statusLabel, style: const TextStyle(color: Colors.white70)),
          if (_establishingNotice != null)
            Padding(
              key: const ValueKey('connection-establishing'),
              padding: const EdgeInsets.only(top: 8, left: 24, right: 24),
              child: Text(
                _establishingNotice!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
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
  /// （発信中・接続中）の間は背景が黒いだけになる為、中央にアバターを重ねて
  /// 音声通話と同じように相手が誰かを常に視認出来るようにする。
  Widget _videoBody(ColorScheme colorScheme, Color placeholderColor) {
    final isConnected = _controller.state == CallConnectionState.active;
    final mainRenderer = _mainViewIsRemote
        ? _controller.remoteRenderer
        : _controller.localRenderer;
    final pipRenderer = _mainViewIsRemote
        ? _controller.localRenderer
        : _controller.remoteRenderer;

    // 音声⇔ビデオの切替は自分・相手それぞれ独立している為、映像が無い側
    // （自分が音声のみ、又は相手が音声のみ）はプレースホルダーで表示する。
    final mainShowsPlaceholder = _mainViewIsRemote
        ? !_remoteIsVideo
        : !_myIsVideo;
    final pipShowsPlaceholder = _mainViewIsRemote
        ? !_myIsVideo
        : !_remoteIsVideo;

    void swapViews() => setState(() => _mainViewIsRemote = !_mainViewIsRemote);

    return Stack(
      children: [
        // 相手の映像を出していない間も、相手の音声を鳴らす（2026-10-31追加）。
        // 出し入れで後ろの子の位置がずれ、自分の映像が作り直されて空になる為、
        // 常に同じ位置に置く（空なら何も描かない）。
        Positioned(
          key: const ValueKey('audio-sink'),
          left: 0,
          top: 0,
          child: CallAudioSinks(
            renderers: _remoteIsVideo ? [] : [_controller.remoteRenderer],
          ),
        ),
        Positioned.fill(
          key: const ValueKey('main-view'),
          child: GestureDetector(
            // 大きい映像のタップで拡大表示（入れ替えは小窓、2026-11-03変更）。
            onTap: mainShowsPlaceholder
                ? null
                : () => showCallVideoViewer(
                    context,
                    renderer: mainRenderer,
                    mirror: !_mainViewIsRemote && _controller.isFrontCamera,
                    onClosed: () {
                      if (mounted) setState(() => _viewerGeneration++);
                    },
                  ),
            child: mainShowsPlaceholder
                ? Container(
                    color: placeholderColor,
                    // 発信中・接続中は、下の「接続中」の表示がアバターを出すので、ここでは
                    // 出さない（二重になるため、2026-11-15）。
                    child: isConnected
                        ? Center(
                            child: _placeholderAvatar(
                              remote: _mainViewIsRemote,
                              radius: 56,
                            ),
                          )
                        : null,
                  )
                : ColoredBox(
                    color: placeholderColor,
                    child: LayoutBuilder(
                      builder: (context, constraints) => RTCVideoView(
                        // Web版のRTCVideoViewはStatefulWidgetで、実描画に使う
                        // videoElementをinitState時にしか取得しない。keyが無いと
                        // メイン/コーナーを入れ替えてもFlutterが同じStateを使い
                        // 回してしまい、映像が入れ替わらずミラー表示だけが
                        // 切り替わって見える不具合になっていた。レンダラーの
                        // 実体が変わったら必ず作り直されるよう、レンダラー自体を
                        // キーにする。
                        key: ValueKey((mainRenderer, _viewerGeneration)),
                        mainRenderer,
                        mirror: !_mainViewIsRemote && _controller.isFrontCamera,
                        // 横長の領域は映像全体を見せる（余白は背景の灰色、2026-10-11
                        // 変更）。縦長の領域は画面いっぱいに切り抜く（2026-10-30）。
                        objectFit: callVideoFitFor(
                          portraitArea:
                              constraints.maxHeight > constraints.maxWidth,
                          main: true,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        if (!isConnected)
          Center(
            key: const ValueKey('connecting'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CallParticipantAvatar(
                  userId: _otherUserId,
                  rhingSeed: _otherRhingSeed,
                  conversationId: widget.call.dmId,
                  radius: 56,
                  fontSize: 40,
                ),
                const SizedBox(height: 16),
                CallParticipantNameLabel(
                  userId: _otherUserId,
                  rhingSeed: _otherRhingSeed,
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
        if (_establishingNotice != null)
          Positioned(
            key: const ValueKey('connection-establishing'),
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, left: 12, right: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _establishingNotice!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        if (isConnected && _controller.connectionIssue)
          Positioned(
            key: const ValueKey('connection-issue'),
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
                  child: Text(
                    ref.read(appStringsProvider).callConnectionUnstableEllipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        SafeArea(
          key: const ValueKey('overlay-controls'),
          child: Column(
            children: [
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _controls(colorScheme),
              ),
            ],
          ),
        ),
        // 相手がミュート中だけ、左上に小さなマイクオフを出す（呼び名・状態の文字は出さない）。
        if (_controller.remoteMuted)
          SafeArea(
            key: const ValueKey('remote-muted'),
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mic_off,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        // 自分の小窓。ミニ表示と同じ方式で、押した瞬間から指に追従して動く。タップで入れ替え。
        Positioned.fill(
          key: const ValueKey('pip'),
          child: SafeArea(
            child: _DraggablePip(
              onTap: swapViews,
              child: Container(
                width: _DraggablePip.width,
                height: _DraggablePip.height,
                color: placeholderColor,
                child: pipShowsPlaceholder
                    ? Center(
                        child: _placeholderAvatar(
                          remote: !_mainViewIsRemote,
                          radius: 28,
                        ),
                      )
                    : RTCVideoView(
                        key: ObjectKey(pipRenderer),
                        pipRenderer,
                        mirror: _mainViewIsRemote && _controller.isFrontCamera,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
              ),
            ),
          ),
        ),
      ],
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
      screenShare: oneToOneScreenShare(_controller, widget.currentUserId),
      remoteBgm: _controller.remoteBgm,
      videoFailed: _controller.videoFailed,
    );
  }
}

/// ビデオ通話の自分の小窓（2026-11-15）。ミニ表示（`_PinnedCallDragSurface`）と同じ方式:
/// 押した瞬間から追従（`DragStartBehavior.down`）し、掴んだ位置を保持して毎回ポインターの
/// 絶対位置から位置を求める。位置は[ValueNotifier]で持ち、動かすたびに`Positioned`だけを
/// 再配置して、中身の映像や画面全体は作り直さない。離しても端へ寄らず、その位置に残る。
class _DraggablePip extends StatefulWidget {
  const _DraggablePip({required this.child, required this.onTap});

  static const width = 90.0;
  static const height = 130.0;

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_DraggablePip> createState() => _DraggablePipState();
}

class _DraggablePipState extends State<_DraggablePip> {
  /// 左上の位置（領域内の座標）。nullなら右上の初期位置。
  final ValueNotifier<Offset?> _offset = ValueNotifier(null);
  Offset? _grab;
  int? _pointer;
  Offset? _downAt;
  bool _dragging = false;

  /// これを超えて動いたらドラッグ、動かずに離したらタップ。
  static const _dragSlop = 6.0;

  void _resetPointer() {
    _pointer = null;
    _downAt = null;
    _grab = null;
    _dragging = false;
  }

  /// 下のボタン列に重ならない範囲まで。
  static const _bottomReserve = 120.0;
  static const _margin = 16.0;
  static const _bubble = Size(_DraggablePip.width, _DraggablePip.height);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  Offset _clamp(Offset? offset, Size area) => clampPinnedCallOffset(
    offset: offset ?? Offset(area.width - _bubble.width - _margin, _margin),
    screen: Size(area.width, area.height - _bottomReserve),
    topInset: 0,
    bubble: _bubble,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final area = Size(c.maxWidth, c.maxHeight);
        return ValueListenableBuilder<Offset?>(
          valueListenable: _offset,
          // 中身（映像）は作り直さない。
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: widget.child,
            ),
          ),
          builder: (context, offset, child) {
            final pos = _clamp(offset, area);
            return Stack(
              children: [
                Positioned(
                  left: pos.dx,
                  top: pos.dy,
                  // 標準のタップ/パン判定は、パンが36px動くまで始まらず、その手前の動きが
                  // 無反応になる為、生のポインターで自前判定する（6pxを超えたら即ドラッグ、
                  // 動かずに離したらタップ）。
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) {
                      if (_pointer != null) return;
                      _pointer = e.pointer;
                      _downAt = e.position;
                      _dragging = false;
                      _grab = e.position - _clamp(_offset.value, area);
                    },
                    onPointerMove: (e) {
                      if (e.pointer != _pointer) return;
                      if (!_dragging &&
                          (e.position - _downAt!).distance > _dragSlop) {
                        _dragging = true;
                      }
                      final grab = _grab;
                      if (_dragging && grab != null) {
                        _offset.value = _clamp(e.position - grab, area);
                      }
                    },
                    onPointerUp: (e) {
                      if (e.pointer != _pointer) return;
                      final wasDrag = _dragging;
                      _resetPointer();
                      if (!wasDrag) widget.onTap();
                    },
                    onPointerCancel: (e) {
                      if (e.pointer == _pointer) _resetPointer();
                    },
                    child: child,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
