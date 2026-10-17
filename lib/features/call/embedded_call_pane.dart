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
import '../../providers/chat_navigation_providers.dart';
import '../../utils/platform_info.dart';
import '../../widgets/pane_visibility.dart';
import '../../widgets/swipe_gestures.dart';
import 'active_call_session.dart';
import 'call_avatar.dart';
import 'call_control_bar.dart';
import 'call_tile_layout.dart';
import 'call_controls.dart';
import 'camera_availability.dart';
import 'webrtc_call_controller.dart';
import 'webrtc_group_call_controller.dart';
import '../../router/back_stack.dart';
import '../../l10n/strings.dart';

/// PC/Web限定: 通話中の会話画面で、メッセージ一覧の代わりに通話UIを
/// 埋め込み表示する（2026-08-19追加、通話UIの再設計に伴う）。
/// `DmChatPane`/`GroupChatPane`が[child]（通常のチャット画面）をこれで
/// 包み、[conversation]に一致する通話セッションが存在しPC/Webである間だけ
/// 通話UIへ差し替える。マウント中は`activeConversationProvider`へ自分の
/// 会話を報告し（`PinnedCallOverlay`が「今その会話を見ているか」を
/// 判定するのに使う）、アンマウント時にクリアする。
class EmbeddedCallPane extends ConsumerStatefulWidget {
  const EmbeddedCallPane({
    required this.conversation,
    required this.roomId,
    required this.child,
    super.key,
  });

  final ViewedConversation conversation;

  /// このペインが今表示している寄合。通話画面は通話の寄合（[callRoomIdProvider]）
  /// を表示している間だけ出し、他の寄合ではメッセージ表示にする（2026-10-13）。
  final String roomId;
  final Widget child;

  @override
  ConsumerState<EmbeddedCallPane> createState() => _EmbeddedCallPaneState();
}

class _EmbeddedCallPaneState extends ConsumerState<EmbeddedCallPane> {
  /// 通話UIとメッセージ一覧、どちらを表示中か（通話中のみ意味を持つ
  /// トグル、`_Header`の「メッセージに戻る」ボタンで切り替える）。
  bool _showingCall = true;

  @override
  void initState() {
    super.initState();
    // `late final`の遅延初期化を、`dispose()`より前（マウント中）に確定させる。
    _activeConversation;
    _embeddedCallShown;
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void didUpdateWidget(covariant EmbeddedCallPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation != widget.conversation ||
        oldWidget.roomId != widget.roomId) {
      _showingCall = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    }
  }

  void _report() {
    if (!mounted) return;
    ref.read(activeConversationProvider.notifier).set(widget.conversation);
  }

  /// 直近に`embeddedCallShownProvider`へ報告した会話。会話の切り替えでこの
  /// `State`が再利用される（`didUpdateWidget`）場合に、**旧会話の報告を確実に
  /// 解除する**ために覚えておく（以前は新しい会話に対して解除しており、旧会話の
  /// 報告が残ってミニ表示が出なくなっていた、2026-10-11修正）。
  ViewedConversation? _reported;

  /// 通話UIを**実際に画面に表示している**間だけ、その会話を
  /// `embeddedCallShownProvider`へ報告する（右上のミニ表示を隠す判定に使う、
  /// 2026-10-11）。ビルド中にプロバイダーを書き換えないよう、フレーム後に反映する。
  void _syncShown(bool shown) {
    final target = shown ? widget.conversation : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(embeddedCallShownProvider.notifier);
      final previous = _reported;
      if (previous != null && previous != target) {
        notifier.clearIfCurrent(previous);
      }
      if (target != null) notifier.set(target);
      _reported = target;
    });
  }

  // `dispose()`では`ref`を使えない（Riverpod 3系は`context.mounted`が偽のため
  // `StateError`を投げる。破棄のたびに例外が出て、後続の破棄・再構築を巻き込んで
  // いた、2026-10-13修正）。後始末に使う通知先を先にフィールドへ保存しておく。
  late final _activeConversation = ref.read(
    activeConversationProvider.notifier,
  );
  late final _embeddedCallShown = ref.read(embeddedCallShownProvider.notifier);

  @override
  void dispose() {
    // `dispose()`中はプロバイダーを書き換えられない（ツリーの構築中扱いで
    // `FlutterError`になる）ため、直後のマイクロタスクで解除する。
    final conversation = widget.conversation;
    final reported = _reported;
    final activeConversation = _activeConversation;
    final embeddedCallShown = _embeddedCallShown;
    Future<void>.microtask(() {
      try {
        activeConversation.clearIfCurrent(conversation);
        embeddedCallShown.clearIfCurrent(conversation);
        if (reported != null) embeddedCallShown.clearIfCurrent(reported);
      } catch (_) {
        // アプリ全体のプロバイダーが既に破棄された後（テストの片付け等。Riverpodの
        // 破棄済みの例外は型が公開されていないため、全て受ける）は何もしない。
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ミニ表示のクリック等で「この会話の通話UIへ戻って」と要求されたら、
    // メッセージ表示に切り替えていても通話UIへ戻す（2026-10-11追加）。
    ref.listen(callPaneRequestProvider, (previous, next) {
      if (next != null && next.$1 == widget.conversation && !_showingCall) {
        setState(() => _showingCall = true);
      }
    });

    final session = ref.watch(activeCallSessionProvider);
    final callRoomId = ref.watch(callRoomIdProvider);
    // 実際に画面に見えているか。`IndexedStack`は非選択の子もマウントしたまま
    // `TickerMode`も無効にしないため、`PaneVisibility`（語らいタブの詳細ペイン・
    // ホームのタブ）と、ルートに覆われた場合の`TickerMode`の両方で判定する
    // （2026-10-13、以前は`TickerMode`のみで、別の語らい・タブへ移っても旧ペインが
    // 「表示中」と報告し続けプレビューが出なかった）。
    final visible = TickerMode.of(context) && PaneVisibility.of(context);
    final isMatch =
        !isMobileCallPlatform &&
        session != null &&
        session.conversation == widget.conversation &&
        // 通話の寄合（最初に通話画面が表示された寄合）だけに通話画面を出す。
        // まだ決まっていなければ（null）この寄合が候補。
        (callRoomId == null || callRoomId == widget.roomId);

    // 通話画面が初めて実際に見えた寄合を、通話の寄合として記録する。
    if (isMatch && callRoomId == null && visible && _showingCall) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(callRoomIdProvider) == null) {
          ref.read(callRoomIdProvider.notifier).set(widget.roomId);
        }
      });
    }

    _syncShown(isMatch && _showingCall && visible);

    if (!isMatch) return widget.child;

    if (!_showingCall) {
      return Stack(
        children: [
          widget.child,
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: _ReturnToCallChip(
                onTap: () => setState(() => _showingCall = true),
              ),
            ),
          ),
        ],
      );
    }

    // 通話UIを埋め込み表示している間は、ブラウザの戻るでメッセージ表示へ
    // 戻れる（2026-10-04追加、`BackStackController`参照）。
    return BackEntry(
      scope: BackScope.talks,
      active: true,
      layer: true,
      onBack: () => setState(() => _showingCall = false),
      child: _EmbeddedCallView(
        session: session,
        onBackToMessages: () => setState(() => _showingCall = false),
      ),
    );
  }
}

/// メッセージ表示に切り替えた後も、通話中であることと戻る導線を示す
/// 小さなチップ。
class _ReturnToCallChip extends ConsumerWidget {
  const _ReturnToCallChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.call, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                ref.watch(appStringsProvider).callReturnChip,
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmbeddedCallView extends StatefulWidget {
  const _EmbeddedCallView({
    required this.session,
    required this.onBackToMessages,
  });

  final ActiveCallSession session;
  final VoidCallback onBackToMessages;

  @override
  State<_EmbeddedCallView> createState() => _EmbeddedCallViewState();
}

class _EmbeddedCallViewState extends State<_EmbeddedCallView> {
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
              widget.onBackToMessages();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && event.scrollDelta.dy < -2.0) {
                _scrollBackTimer?.cancel();
                _scrollBackTimer = Timer(const Duration(milliseconds: 150), () {
                  if (mounted) widget.onBackToMessages();
                });
              }
            },
            child: SwipeDownToDismiss(
              onDismiss: widget.onBackToMessages,
              // `Material`祖先が無いと`Text`が`DefaultTextStyle`を得られず、
              // 48px・白・黄色の二重下線のフォールバック表示になる（2026-10-13修正）。
              child: Material(
                color: colorScheme.surface,
                child: Column(
                  children: [
                    _Header(onBackToMessages: widget.onBackToMessages),
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
  const _Header({required this.onBackToMessages});
  final VoidCallback onBackToMessages;

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
              onPressed: onBackToMessages,
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
                : null,
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
        if (cornerHasVideo)
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
                    child: _video(remote: !_mainIsRemote, main: false),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GroupStage extends StatelessWidget {
  const _GroupStage({required this.session});
  final GroupCallSession session;

  @override
  Widget build(BuildContext context) {
    final controller = session.controller;
    final tiles = [
      _tile(
        userId: controller.currentUser.userId,
        rhingSeed: controller.currentUser.rhingSeed,
        renderer: controller.isVideo ? controller.localRenderer : null,
        mirror: controller.isFrontCamera,
        videoEnabled: controller.isVideo,
        micMuted: controller.muted,
      ),
      for (final p in controller.remoteParticipants)
        _tile(
          userId: p.userId,
          rhingSeed: p.rhingSeed,
          renderer: controller.remoteRenderers[p.userId],
          mirror: false,
          videoEnabled: p.isVideo,
          micMuted: p.micMuted,
        ),
    ];
    // 領域が縦長（スマホ等）なら縦に積み、横長なら従来のグリッド
    // （`CallTileGrid`、2026-10-13）。
    return CallTileGrid(tiles: tiles);
  }

  Widget _tile({
    required String userId,
    required String rhingSeed,
    required RTCVideoRenderer? renderer,
    required bool mirror,
    required bool videoEnabled,
    required bool micMuted,
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
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : Center(
                  child: CallParticipantAvatar(
                    userId: userId,
                    rhingSeed: rhingSeed,
                    conversationId: session.groupId,
                    radius: 28,
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
