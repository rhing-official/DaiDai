import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/call_display_provider.dart';
import '../../providers/camera_availability_provider.dart';
import '../../router/app_router.dart';
import '../../theme/block/block_theme.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/glass/glass_colors.dart';
import '../../l10n/strings.dart';
import '../../utils/platform_info.dart';
import '../../widgets/gekiga/gekiga_badge.dart';
import '../../widgets/media_preview_frame.dart'
    show GekigaStraightMonochromeBox;
import '../../widgets/glass/glass_surface.dart';
import 'active_call_session.dart';
import 'call_audio_sinks.dart';
import 'call_avatar.dart';
import 'call_ring_ripple.dart';
import 'camera_availability.dart';
import 'pinned_call_position.dart';
import 'webrtc_call_controller.dart';

/// 通話中、通話画面を閉じている間だけ表示する右上固定のミニ表示
/// （2026-08-19追加）。`HomeScreen`の外側`Stack`（ナビチップと同じ階層）に
/// 常時マウントしておくことで、身だしなみ・設定タブへ移動しても消えない
/// （PC・Webで通話画面`CallOverlay`を開いている間は、重複を避けて非表示にする）。
///
/// 表示条件: PCでは通話画面を閉じている間、モバイルでは全画面から下
/// スワイプでドックした間だけ表示する。音声のみの通話も（当初は完全非表示
/// だったが）ビデオ通話と同様に表示する（2026-08-19変更）。映像が無い間は
/// 通話画面の音声通話時と同じ、呼び名の頭文字を乗せた丸いアバターを中央に
/// 表示する（[_PinnedCallBubble]参照）。
/// モバイルのミニ表示で映像を描くか。2026-11-14に、Androidで「ミニ表示にした後、他の画面の
/// タップが効かない・ホーム下のタブが開けない」不具合が出て、映像の描画が原因と分かったため、
/// いったん描かない（アバターを出す）ようにした。2026-11-15に、ユーザーの希望で既定を映像ありに戻し、
/// 負荷を下げる対策（アンチエイリアスのクリップ・影・音声用の動画要素をやめる、映像を独立した
/// 描画層にする）を同時に入れた。再発したら`--dart-define=PINNED_VIDEO=false`のビルドで退避できる。
const kPinnedCallShowsVideoOnMobile = bool.fromEnvironment(
  'PINNED_VIDEO',
  defaultValue: true,
);

/// 【一時的な診断・原因が分かったら削除する】ミニ表示の映像まわりを、ビルド時に切り替える
/// （`--dart-define=PINNED_NOCLIP=true`など、2026-11-14）。計測の比較用。
const kPinnedNoClip = bool.fromEnvironment('PINNED_NOCLIP');
const kPinnedNoSinks = bool.fromEnvironment('PINNED_NOSINKS');

class PinnedCallOverlay extends ConsumerWidget {
  const PinnedCallOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeCallSessionProvider);
    if (session == null) {
      // 通話が終わったら、ドラッグで動かした位置を既定に戻す。
      if (ref.read(pinnedCallOffsetProvider) != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(pinnedCallOffsetProvider.notifier).set(null);
        });
      }
      return const SizedBox.shrink();
    }

    // PC・Webでは、通話画面（`CallOverlay`、今の画面の上に重ねる層）が開いて
    // いる間だけ隠す（2026-10-23、以前は語らいへの埋め込み表示の有無で判定）。
    if (!isMobileCallPlatform && ref.watch(callOverlayOpenProvider)) {
      return const SizedBox.shrink();
    }

    // 一対の着信（応答前）は、ミニ表示ではなく着信バナー
    // （`IncomingCallBannerOverlay`）で知らせる（2026-10-23）。
    if (!isMobileCallPlatform &&
        session is OneToOneCallSession &&
        !session.controller.isCaller &&
        session.controller.state == CallConnectionState.connecting) {
      return const SizedBox.shrink();
    }

    if (isMobileCallPlatform && !session.minimized) {
      return const SizedBox.shrink(); // まだ全画面表示中
    }

    // 設定（端末ごと）で小窓を出さない場合（2026-11-18）。細いチップか何も出さないかだが、
    // どちらでも、映像を持たない参加者の音声は（Webでは見えない動画要素が鳴らすため）鳴らし続ける。
    final miniStyle = ref.watch(callMiniStyleProvider);
    if (miniStyle != CallMiniStyle.video) {
      return ListenableBuilder(
        listenable: session.controllerListenable,
        builder: (context, _) => _PinnedCallLight(
          session: session,
          showChip: miniStyle == CallMiniStyle.bar,
        ),
      );
    }

    // ミュート・映像有無等、コントローラーの状態変化に応じて
    // `_PinnedCallBubble`（マイク/映像アイコンや映像表示）を再描画する
    // ためlistenする。サイズは音声・映像とも常に固定（2026-08-21に映像
    // ありだけ画面下端まで伸ばす仕様にしたが、140幅の極端な縦長比率に
    // 横長のWebカメラ映像を詰め込むと不自然に間延びして見えるとの指摘を
    // 受け、2026-08-30に音声通話と同じ固定サイズへ戻した）。
    final screen = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final position = clampPinnedCallOffset(
      offset: ref.watch(pinnedCallOffsetProvider),
      screen: screen,
      topInset: topInset,
    );
    return ListenableBuilder(
      listenable: session.controllerListenable,
      builder: (context, _) {
        return Positioned(
          left: position.dx,
          top: position.dy,
          // Webでは映像（プラットフォームビュー）がクリックを奪うため、
          // 上に重ねたこのミニ表示が受け取れるようにする（2026-10-11追加）。
          // ドラッグ用のボタンは設けず、ミニ表示そのものを掴んで動かせる
          // （2026-10-11追加）。タップ・内部ボタンは従来どおり動く。
          child: PointerInterceptor(
            child: _PinnedCallDragSurface(
              currentOffset: () => clampPinnedCallOffset(
                offset: ref.read(pinnedCallOffsetProvider),
                screen: screen,
                topInset: topInset,
              ),
              onPointerMoved: (grab, pointer) {
                ref
                    .read(pinnedCallOffsetProvider.notifier)
                    .set(
                      pinnedCallOffsetForPointer(
                        pointer: pointer,
                        grab: grab,
                        screen: screen,
                        topInset: topInset,
                      ),
                    );
              },
              child: _PinnedCallBubble(session: session),
            ),
          ),
        );
      },
    );
  }
}

/// ミニ表示を掴んで動かすための面（2026-10-13）。相対移動（`delta`）の積算では
/// なく、掴んだ位置を保持して常にポインターの絶対位置から位置を求める。
/// `delta`方式は、再描画前に届いた複数のイベントが同じ古い位置に足されて
/// 移動量を失い、また開始閾値（スロップ）分も取りこぼして指に遅れて見えた。
/// `dragStartBehavior.down`で押した瞬間の位置から追従する。
class _PinnedCallDragSurface extends StatefulWidget {
  const _PinnedCallDragSurface({
    required this.currentOffset,
    required this.onPointerMoved,
    required this.child,
  });

  /// 押した時点のミニ表示の左上（画面内に補正済み）。
  final Offset Function() currentOffset;

  /// ドラッグ中、掴んだ位置[grab]（ポインター − 左上）と現在のポインター位置[pointer]。
  final void Function(Offset grab, Offset pointer) onPointerMoved;
  final Widget child;

  @override
  State<_PinnedCallDragSurface> createState() => _PinnedCallDragSurfaceState();
}

class _PinnedCallDragSurfaceState extends State<_PinnedCallDragSurface> {
  Offset? _grab;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      dragStartBehavior: DragStartBehavior.down,
      onPanDown: (details) =>
          _grab = details.globalPosition - widget.currentOffset(),
      onPanUpdate: (details) {
        final grab = _grab;
        if (grab != null) widget.onPointerMoved(grab, details.globalPosition);
      },
      onPanEnd: (_) => _grab = null,
      onPanCancel: () => _grab = null,
      child: widget.child,
    );
  }
}

/// この通話セッションで中央に表示すべき映像（相手優先、無ければ自分）。
/// nullなら映像が無く、[_PinnedCallBubble]はアバターのプレースホルダーを
/// 表示する。
RTCVideoRenderer? pickCallRenderer(ActiveCallSession session) {
  switch (session) {
    case OneToOneCallSession(:final controller):
      if (controller.remoteVideoShown) return controller.remoteRenderer;
      if (controller.isVideo) return controller.localRenderer;
      return null;
    case GroupCallSession(:final controller):
      final pinned = controller.pinnedParticipant;
      // 話している相手が映像オフなら、その人のアイコンを出す（nullを返す）。
      if (pinned != null) {
        return pinned.isVideo
            ? controller.remoteRenderers[pinned.userId]
            : null;
      }
      if (controller.isVideo) return controller.localRenderer;
      return null;
  }
}

/// OS標準のPiPの小窓に出す内容（2026-11-26）。[renderer]がnullなら、相手のアバターを出す。
/// [isScreen]の時は、共有画面を切り取らないよう全体を収めて出す。
class PipContent {
  const PipContent({this.renderer, this.isScreen = false});

  final RTCVideoRenderer? renderer;
  final bool isScreen;
}

/// PiPの小窓に出すもの。相手の共有画面、相手のカメラ、相手のアバターの順で、
/// 自分のカメラ・自分の共有は出さない（アプリ内のミニ表示の[pickCallRenderer]とは別）。
PipContent pickPipContent(ActiveCallSession session) {
  switch (session) {
    case OneToOneCallSession(:final controller):
      if (controller.remoteScreenReady) {
        return PipContent(
          renderer: controller.remoteScreenRenderer,
          isScreen: true,
        );
      }
      if (controller.remoteVideoShown) {
        return PipContent(renderer: controller.remoteRenderer);
      }
      return const PipContent();
    case GroupCallSession(:final controller):
      final sharer = controller.remoteParticipants.firstWhereOrNull(
        controller.remoteScreenReady,
      );
      if (sharer != null) {
        return PipContent(
          renderer: controller.screenRenderers[sharer.userId],
          isScreen: true,
        );
      }
      final pinned = controller.pinnedParticipant;
      if (pinned != null && pinned.isVideo) {
        return PipContent(renderer: controller.remoteRenderers[pinned.userId]);
      }
      return const PipContent();
  }
}

/// 映像が無い間（音声のみの通話、又はビデオ通話でも相手・自分どちらも
/// 映像を出していない間）に中央へ表示するアバター情報（userId・rhingSeed・
/// 会話id）。通話画面の音声通話時（`CallScreen._audioBody`/
/// `GroupCallScreen._audioBody`）と同じ[CallParticipantAvatar]を、
/// 代表1人分だけ小さく表示する（2026-08-19追加、音声通話でもミニ表示を
/// 出すようにした際に追加）。
({String userId, String rhingSeed, String? conversationId}) callPlaceholderInfo(
  ActiveCallSession session,
) {
  switch (session) {
    case OneToOneCallSession(:final call, :final currentUserId):
      return (
        userId: call.otherUserId(currentUserId),
        rhingSeed: call.otherRhingSeed(currentUserId),
        conversationId: call.dmId,
      );
    case GroupCallSession(:final controller, :final groupId):
      final remoteRepresentative =
          controller.pinnedParticipant ??
          controller.remoteParticipants.firstOrNull;
      return (
        userId: remoteRepresentative?.userId ?? controller.currentUser.userId,
        rhingSeed:
            remoteRepresentative?.rhingSeed ?? controller.currentUser.rhingSeed,
        conversationId: groupId,
      );
  }
}

/// ネイティブのモバイルで映像を出す時の軽量化を行うか（音声用の動画要素はWebの都合のもの）。
bool get _lightMobileVideo =>
    !kIsWeb && isMobileCallPlatform && kPinnedCallShowsVideoOnMobile;

class _PinnedCallBubble extends ConsumerWidget {
  const _PinnedCallBubble({required this.session});

  final ActiveCallSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skipVideo = isMobileCallPlatform && !kPinnedCallShowsVideoOnMobile;
    final renderer = skipVideo ? null : pickCallRenderer(session);
    final placeholder = callPlaceholderInfo(session);
    final muted = switch (session) {
      OneToOneCallSession(:final controller) => controller.muted,
      GroupCallSession(:final controller) => controller.muted,
    };
    final isVideo = switch (session) {
      OneToOneCallSession(:final controller) => controller.isVideo,
      GroupCallSession(:final controller) => controller.isVideo,
    };
    final switchingCallType = switch (session) {
      OneToOneCallSession(:final controller) => controller.switchingCallType,
      GroupCallSession(:final controller) => controller.switchingCallType,
    };
    // 表示中の映像が自分のものなら、前面カメラの時だけ左右反転させる
    // （2026-08-30追加、通話画面（call_screen.dart等）と同じ考え方。
    // 背面カメラの映像まで反転すると実際の景色と左右が逆になり不自然）。
    final localRenderer = switch (session) {
      OneToOneCallSession(:final controller) => controller.localRenderer,
      GroupCallSession(:final controller) => controller.localRenderer,
    };
    final isFrontCamera = switch (session) {
      OneToOneCallSession(:final controller) => controller.isFrontCamera,
      GroupCallSession(:final controller) => controller.isFrontCamera,
    };
    final mirror = renderer == localRenderer && isFrontCamera;
    final cameraAvailability =
        ref.watch(cameraAvailabilityProvider).value ??
        CameraAvailability.unknown;
    final videoToggleVisible =
        cameraAvailability != CameraAvailability.unavailable;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;

    // 広場通話は、映像を出している1人以外の参加者の音声も鳴らす（2026-10-21、
    // ミニ表示中は1人分の映像しか載らず、他の参加者の音声が聞こえなかった）。
    // 映像を描かないモバイルでは、音声用の見えない動画要素も出さない（Webの都合のもの）。
    final audioOnly = (skipVideo || kPinnedNoSinks || _lightMobileVideo)
        ? const <RTCVideoRenderer>[]
        : switch (session) {
            GroupCallSession(:final controller) => [
              for (final r in controller.remoteRenderers.values)
                if (r != renderer) r,
            ],
            OneToOneCallSession(:final controller) => [
              if (renderer != controller.remoteRenderer)
                controller.remoteRenderer,
            ],
          };

    final content = Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          top: 0,
          child: CallAudioSinks(renderers: audioOnly),
        ),
        if (renderer != null)
          // 毎フレーム更新される映像を独立した描画層にして、周囲（ボタン行など）を再描画させない。
          RepaintBoundary(
            child: RTCVideoView(
              key: ObjectKey(renderer),
              renderer,
              mirror: mirror,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          )
        else
          Center(
            // 一対でまだ繋がっていない間（呼び出し中・確立待ち）は、相手のアイコンの周りに
            // 波紋を出す（2026-11-18、通話画面と同じ）。
            child: CallRingingAvatar(
              ringing: switch (session) {
                OneToOneCallSession(:final controller) =>
                  !controller.mediaConnected &&
                      controller.state != CallConnectionState.ended,
                _ => false,
              },
              radius: 36,
              reachFactor: 1.5,
              avatar: CallParticipantAvatar(
                userId: placeholder.userId,
                rhingSeed: placeholder.rhingSeed,
                conversationId: placeholder.conversationId,
                radius: 36,
                fontSize: 28,
              ),
            ),
          ),
        // 通話画面（CallControlBar）と同じ相対順序（マイク→カメラ→
        // 切断）で1本の行にまとめ、映像領域の下端に浮かせる
        // （2026-08-20追加）。以前は切断を右上・マイクを左下に散らして
        // いたが、通話画面と並びを揃える為に統一した。
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _MiniIconButton(
                icon: muted ? Icons.mic_off : Icons.mic,
                color: isGekiga || isGlass ? Colors.grey[700]! : Colors.black54,
                isGekiga: isGekiga,
                isGlass: isGlass,
                onTap: () {
                  switch (session) {
                    case OneToOneCallSession(:final controller):
                      controller.toggleMute();
                    case GroupCallSession(:final controller):
                      controller.toggleMute();
                  }
                },
              ),
              _MiniIconButton(
                icon: isVideo ? Icons.videocam : Icons.videocam_off,
                color: isGekiga || isGlass ? Colors.grey[700]! : Colors.black54,
                isGekiga: isGekiga,
                isGlass: isGlass,
                enabled: !switchingCallType,
                visible: videoToggleVisible,
                onTap: () {
                  switch (session) {
                    case OneToOneCallSession(:final controller):
                      controller.setVideoEnabled(!controller.isVideo);
                    case GroupCallSession(:final controller):
                      controller.setVideoEnabled(!controller.isVideo);
                  }
                },
              ),
              _MiniIconButton(
                icon: Icons.call_end,
                color: Colors.red,
                isGekiga: isGekiga,
                isGlass: isGlass,
                onTap: () =>
                    ref.read(activeCallSessionProvider.notifier).endCall(),
              ),
            ],
          ),
        ),
      ],
    );

    final bubbleSize = SizedBox(width: 140, height: 200, child: content);

    if (isGekiga) {
      // 通話画面のCallControlBar/CallRoundButtonと同じく、劇画スタイルの
      // 「黒外枠→白内枠」のモノクロボックス（GekigaPhotoFrameと同じ部品）で
      // 縁取る。丸角・Material elevationの影は劇画の他要素同様に使わない
      // （2026-08-30修正、新規追加時に劇画・ガラス対応のスイープから漏れて
      // いた）。
      return GestureDetector(
        onTap: () => _reopen(context, ref),
        // 通話画面の他のパネル（BGM・画面共有のシート、`CallPanelSurface`）と同じ
        // 直角のモノクロボックス（白枠→黒線→黒地）で縁取る。
        child: GekigaStraightMonochromeBox(
          isMe: false,
          child: SizedBox(width: 134, height: 194, child: content),
        ),
      );
    }

    if (isGlass) {
      // 他の浮遊ポップアップ・ダイアログと同じ`GlassVariant.floating`で
      // 縁の光る線を出す（2026-08-30追加、新規追加時に劇画対応と同時に
      // 対応すべきだったガラス対応漏れ）。
      return GlassSurface(
        variant: GlassVariant.floating,
        borderRadius: BorderRadius.circular(16),
        // `InkWell`には`Material`祖先が要る。ミニ表示は`main.dart`のbuilder
        // （`Scaffold`の外）に置いているため自前で持つ（2026-10-13修正）。
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(onTap: () => _reopen(context, ref), child: bubbleSize),
        ),
      );
    }

    // モバイルで映像を出す時は、影（elevation）とアンチエイリアス付きのクリップ（別レイヤーへ描いて
    // 合成する）をやめ、`hardEdge`で角丸に切る（負荷を下げる、2026-11-15）。
    return Material(
      elevation: (kPinnedNoClip || _lightMobileVideo) ? 0 : 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: kPinnedNoClip
          ? Clip.none
          : (_lightMobileVideo ? Clip.hardEdge : Clip.antiAlias),
      color: Colors.grey.shade900,
      child: InkWell(onTap: () => _reopen(context, ref), child: bubbleSize),
    );
  }

  void _reopen(BuildContext context, WidgetRef ref) =>
      reopenActiveCall(ref.read, session);
}

/// 進行中の通話の画面を開き直す（ミニ表示のタップ、通話中の再発信の代わり）。
/// モバイルは全画面へ戻し、PC・Webは今の画面の上に重ねる。
void reopenActiveCall(
  T Function<T>(ProviderListenable<T> provider) read,
  ActiveCallSession session,
) {
  if (isMobileCallPlatform) {
    // ドック中なら全画面へ戻す（同じセッションへ再アタッチする経路は
    // 各画面のinitStateが冪等に処理する為、Argsの中身は起動時と同じ
    // 形で渡せば良い）。
    read(activeCallSessionProvider.notifier).setMinimized(false);
    final router = read(goRouterProvider);
    switch (session) {
      case OneToOneCallSession(
        :final call,
        :final isCaller,
        :final currentUserId,
      ):
        router.push(
          '/call',
          extra: CallArgs(
            call: call,
            isCaller: isCaller,
            currentUserId: currentUserId,
          ),
        );
      case GroupCallSession(
        :final controller,
        :final groupCallId,
        :final groupId,
      ):
        router.push(
          '/group-call',
          extra: GroupCallArgs(
            groupCallId: groupCallId,
            groupId: groupId,
            currentUser: controller.currentUser,
            isVideo: controller.isVideo,
          ),
        );
    }
    return;
  }

  // PC・Webでは画面を移動せず、今の画面の上に通話画面を重ねて開く
  // （2026-10-23、以前は語らいタブへ移動して通話中の寄合を開いていた）。
  read(callOverlayOpenProvider.notifier).open();
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.color,
    required this.isGekiga,
    required this.isGlass,
    required this.onTap,
    this.enabled = true,
    this.visible = true,
  });

  final IconData icon;
  final Color color;
  final bool isGekiga;
  final bool isGlass;
  final VoidCallback onTap;

  /// タップを一時的に無効化する（枠は残したまま暗く表示、
  /// `call_controls.dart`の`CallRoundButton`のenabled/disabled表現の簡易版）。
  final bool enabled;

  /// falseの場合、`CallControlBar`の`_maybeHidden`と同じく枠のスペースだけ
  /// 残して見た目とタップ判定を消す（アイコン行の並びが動かないようにする
  /// ため）。
  final bool visible;

  @override
  Widget build(BuildContext context) {
    // 劇画スタイルは`CallRoundButton`の劇画分岐と同じ`GekigaBadgeShape`
    // （手描き風モノクロボックス）、ガラススタイルは同じく`CallRoundButton`の
    // ガラス分岐と同じ`GlassSurface`の円形パネルに切り替える（2026-08-30
    // 追加、新規追加時にどちらの対応スイープからも漏れていた）。
    final Widget button;
    if (isBlockTheme(context)) {
      // 版画は`CallRoundButton`と同じ黒の太枠＋硬い影の小さな箱（2026-11-06）。
      final scheme = Theme.of(context).colorScheme;
      final destructive = color == Colors.red;
      button = Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          width: 28,
          height: 28,
          child: blockMaterialBox(
            context,
            color: destructive
                ? Colors.red.shade700
                : (Theme.of(context).brightness == Brightness.light
                      ? Colors.white
                      : scheme.surface),
            radius: 8,
            shadowOffset: const Offset(2, 2),
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: Center(
                child: Icon(
                  icon,
                  size: 14,
                  color: destructive ? Colors.white : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    } else if (isGekiga) {
      button = Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: GekigaBadgeShape(
                color: color,
                seed: icon.hashCode,
                child: Icon(icon, color: GekigaColors.onPanel, size: 14),
              ),
            ),
          ),
        ),
      );
    } else if (isGlass) {
      button = Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          width: 28,
          height: 28,
          child: GlassSurface(
            variant: GlassVariant.card,
            opaque: true,
            borderRadius: BorderRadius.circular(14),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? onTap : null,
                child: Center(
                  child: Icon(
                    icon,
                    color: GlassColors.adaptiveIconColor(
                      color,
                      Theme.of(context).brightness,
                    ),
                    size: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      button = Material(
        color: enabled ? color : Colors.black26,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon, color: Colors.white, size: 16),
          ),
        ),
      );
    }
    if (visible) return button;
    return IgnorePointer(child: Opacity(opacity: 0, child: button));
  }
}

/// ミニ表示を「細いチップ」「出さない」にしている時の表示（2026-11-18）。チップは画面右上に
/// 小さく出し、タップで通話画面へ戻る。映像は描かない。リモートの音声を鳴らす見えない動画要素
/// だけは、小窓と同じ条件で残す。
class _PinnedCallLight extends ConsumerWidget {
  const _PinnedCallLight({required this.session, required this.showChip});

  final ActiveCallSession session;
  final bool showChip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skipSinks = kPinnedNoSinks || _lightMobileVideo;
    final sinks = skipSinks
        ? const <RTCVideoRenderer>[]
        : switch (session) {
            GroupCallSession(:final controller) => [
              ...controller.remoteRenderers.values,
            ],
            OneToOneCallSession(:final controller) => [
              controller.remoteRenderer,
            ],
          };
    final sinkWidget = CallAudioSinks(renderers: sinks);
    if (!showChip) {
      return Positioned(left: 0, top: 0, child: sinkWidget);
    }

    final strings = ref.watch(appStringsProvider);
    final scheme = Theme.of(context).colorScheme;
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final bg = isGekiga ? GekigaColors.onPanel : scheme.primary;
    final fg = isGekiga ? GekigaColors.panel : scheme.onPrimary;
    final muted = switch (session) {
      OneToOneCallSession(:final controller) => controller.muted,
      GroupCallSession(:final controller) => controller.muted,
    };
    // ドラッグで動かせる（小窓と同じ位置の状態を共用、2026-11-18）。動かすまでは右上。
    final screen = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final offset = ref.watch(pinnedCallOffsetProvider);
    final position = offset == null
        ? null
        : clampPinnedCallOffset(
            offset: offset,
            screen: screen,
            topInset: topInset,
            bubble: kPinnedChipSize,
          );
    return Positioned(
      top: position?.dy ?? topInset + kPinnedCallMargin,
      left: position?.dx,
      right: position == null ? kPinnedCallMargin : null,
      child: PointerInterceptor(
        child: _PinnedCallDragSurface(
          currentOffset: () {
            // 右上の既定の位置で掴んだ時は、そこからの相対で動かす（チップの幅は概算）。
            final current = ref.read(pinnedCallOffsetProvider);
            return clampPinnedCallOffset(
              offset:
                  current ??
                  Offset(
                    screen.width - kPinnedChipSize.width - kPinnedCallMargin,
                    topInset + kPinnedCallMargin,
                  ),
              screen: screen,
              topInset: topInset,
              bubble: kPinnedChipSize,
            );
          },
          onPointerMoved: (grab, pointer) {
            ref
                .read(pinnedCallOffsetProvider.notifier)
                .set(
                  pinnedCallOffsetForPointer(
                    pointer: pointer,
                    grab: grab,
                    screen: screen,
                    topInset: topInset,
                    bubble: kPinnedChipSize,
                  ),
                );
          },
          child: Material(
            color: bg,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => reopenActiveCall(ref.read, session),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          muted ? Icons.mic_off : Icons.call,
                          size: 16,
                          color: fg,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          strings.callPresenceChipLabel,
                          style: TextStyle(
                            color: fg,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Positioned(left: 0, top: 0, child: sinkWidget),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
