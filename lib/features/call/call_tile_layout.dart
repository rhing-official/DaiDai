import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart'
    show GestureBinding, PointerDownEvent, PointerEvent, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show
        MediaStreamTrack,
        RTCVideoRenderer,
        RTCVideoValue,
        RTCVideoView,
        RTCVideoViewObjectFit;
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../l10n/strings.dart';
import 'call_pin_provider.dart';

/// 自分の画面共有のウィンドウの中身に出す「画面を共有しています」（2026-11-16）。Androidの
/// ウィンドウの名前ラベルに添える、マイクの状態の表示（2026-11-16）。ミュート中はマイクオフのアイコン、
/// 他のアプリにマイクを奪われて声が届かない時は「マイクを使えません」（ミュートとは別の表示）。
class CallMicStatus extends ConsumerWidget {
  const CallMicStatus({
    required this.muted,
    required this.unavailable,
    super.key,
  });

  final bool muted;
  final bool unavailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!muted && !unavailable) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (muted)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.mic_off, size: 14, color: Colors.white),
          ),
        if (unavailable)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: Colors.amber,
                ),
                const SizedBox(width: 2),
                Text(
                  ref.watch(appStringsProvider).callMicUnavailableLabel,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 自分のマイクの案内（バナー）。他のアプリにマイクを奪われている間（[unavailable]）と、
/// 通話に入る時に他のアプリが使っていた間（[busyAtJoin]）だけ出す。
class CallMicBanner extends ConsumerWidget {
  const CallMicBanner({
    required this.unavailable,
    required this.busyAtJoin,
    super.key,
  });

  final bool unavailable;
  final bool busyAtJoin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!unavailable && !busyAtJoin) return const SizedBox.shrink();
    final strings = ref.watch(appStringsProvider);
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: Colors.amber,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                unavailable
                    ? strings.callMicUnavailableBanner
                    : strings.callMicBusyAtJoinBanner,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// アプリは端末の画面全体を撮る為、自分の共有の映像をこの画面に出すと、撮られた画面の中に
/// 同じ映像がまた映り続ける（無限鏡で、描画の負荷も上がる）。映像の代わりにこれを出す。
class ScreenSharingNowView extends ConsumerWidget {
  const ScreenSharingNowView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.screen_share, color: Colors.white70, size: 40),
          const SizedBox(height: 8),
          Text(
            ref.watch(appStringsProvider).callScreenSharingNow,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Androidで、自分が共有している画面のプレビュー（2026-11-16）。画面全体を共有している時、ライブの映像を
/// この画面に出すと無限に入れ子になって重くなる為、既定は**1秒に1回だけ取る静止画**にする。1つのアプリを
/// 共有している人は、右下のボタンでライブ表示にできる（画面全体か1つのアプリかは、アプリから判定できない）。
/// 最初の静止画が取れるまでは、[ScreenSharingNowView]のカードを出す。
class ScreenSharePreview extends ConsumerStatefulWidget {
  const ScreenSharePreview({
    required this.trackOf,
    required this.liveRenderer,
    super.key,
  });

  /// 共有している映像のトラック（共有していなければnull）。
  final MediaStreamTrack? Function() trackOf;

  /// ライブ表示に使う、自分の共有の描画の部品。
  final RTCVideoRenderer liveRenderer;

  @override
  ConsumerState<ScreenSharePreview> createState() => _ScreenSharePreviewState();
}

class _ScreenSharePreviewState extends ConsumerState<ScreenSharePreview> {
  Uint8List? _still;
  bool _live = false;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _capture();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _capture());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 静止画を1枚取る。前回が終わっていなければ取らない（画面が静止してフレームが来ない間は
  /// 完了しないことがある為、完了を待ち、取得が溜まらないようにする）。失敗しても前の画像のまま。
  Future<void> _capture() async {
    if (_live || _busy) return;
    final track = widget.trackOf();
    if (track == null) return;
    _busy = true;
    try {
      final buffer = await track.captureFrame();
      if (!mounted) return;
      setState(() => _still = buffer.asUint8List());
    } catch (_) {
      // 前の画像のまま。
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final still = _still;
    final Widget picture = _live
        ? RTCVideoView(
            widget.liveRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          )
        : still != null
        ? Image.memory(
            still,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            width: double.infinity,
            height: double.infinity,
          )
        : const ScreenSharingNowView();
    return Stack(
      fit: StackFit.expand,
      children: [
        picture,
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                key: const ValueKey('screen-preview-live'),
                tooltip: _live
                    ? strings.callScreenPreviewStillTooltip
                    : strings.callScreenPreviewLiveTooltip,
                icon: Icon(
                  _live ? Icons.videocam : Icons.videocam_off,
                  color: Colors.white,
                  size: 18,
                ),
                onPressed: () => setState(() => _live = !_live),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 相手の画面共有のウィンドウの、映像が届くまでの表示（2026-11-16）。配信が始まったことは先に
/// 分かるが、映像のストリームは再ネゴシエーションを経て数秒遅れて届く。届かない時は[failed]で案内。
class ScreenReceivingView extends ConsumerWidget {
  const ScreenReceivingView({this.failed = false, super.key});

  final bool failed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (failed)
              const Icon(Icons.error_outline, color: Colors.white70, size: 32)
            else
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white70,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              failed
                  ? strings.callScreenShareReceiveFailed
                  : strings.callScreenShareReceiving,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// 通話のウィンドウ（参加者・画面共有）の1行あたりの枚数（上の行から、2026-11-16）。
/// 一対・広場で共通の規則。画面共有も1枚と数える（2人が両方共有なら4枚）。
///
/// - 縦長（[portrait]）: 1=[1]、2=[1,1]、3以上は1行2枚で、奇数は最上行が1枚。
/// - 横長: 1=[1]、2=[2]、3〜8は2行（上=n÷2の切り捨て、下=残り。3=[1,2]、5=[2,3]、6=[3,3]）、
///   9以上は1行最大4枚で、余りは最上行（9=[1,4,4]）。
///
/// 0枚は`null`。
List<int>? callTileRowSizes(int count, {required bool portrait}) {
  if (count <= 0) return null;
  if (count == 1) return const [1];
  if (portrait) {
    if (count == 2) return const [1, 1];
    final sizes = List.filled((count / 2).ceil(), 2);
    if (count.isOdd) sizes[0] = 1;
    return sizes;
  }
  if (count == 2) return const [2];
  if (count <= 8) {
    final top = count ~/ 2;
    return [top, count - top];
  }
  final rows = (count / 4).ceil();
  final sizes = List.filled(rows, 4);
  sizes[0] = count - 4 * (rows - 1);
  return sizes;
}

/// 通話の1枚のウィンドウ（参加者・画面共有）の指定。[key]は、参加者は`userId`、画面共有は
/// `<userId>#screen`（一対は`self`・`remote`・`self#screen`・`remote#screen`）。
class CallTileSpec {
  const CallTileSpec({required this.key, required this.build, this.volume});

  final String key;

  /// ウィンドウの中身。[pinned]は、ピン留めされて大きく出している時（アイコンの大きさ・
  /// 映像の収め方を変える）。
  final Widget Function(bool pinned) build;

  /// このウィンドウの音量（2026-11-16）。指定があるウィンドウにだけ、右下に音量のボタンを出す
  /// （押すとスライダーが開く）。相手の声・相手の共有音声は聞こえる音量、自分・自分の共有は
  /// 相手へ送る音量（Webのみ）。
  final CallTileVolume? volume;
}

/// ウィンドウの音量（0〜1）。
class CallTileVolume {
  const CallTileVolume({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;
}

/// 通話のウィンドウの配置（2026-11-16）。与えられた領域に**スクロール無しで常に収まる**。
/// 並べ方は[callTileRowSizes]。画面共有は呼び出し側が先頭に置く（＝最上行）。
/// ピン留めしたウィンドウは領域の上の大きい部分に並べ、残りは下の細い1行の帯に並べる。
/// ピンのボタンは、各ウィンドウの左上にここで重ねる。
class CallTileStage extends ConsumerStatefulWidget {
  const CallTileStage({required this.specs, this.spacing = 4.0, super.key});

  final List<CallTileSpec> specs;
  final double spacing;

  @override
  ConsumerState<CallTileStage> createState() => _CallTileStageState();
}

class _CallTileStageState extends ConsumerState<CallTileStage> {
  /// ピンで並びが変わっても、映像（Webの描画要素）を作り直さないよう、ウィンドウごとに
  /// 付け替えても同じ状態を保つ`GlobalKey`。
  final Map<String, GlobalKey> _keys = {};

  /// 音量のスライダーを開いているウィンドウのキー。
  final Set<String> _volumeOpen = {};

  /// 開いているスライダーの枠と音量ボタンの位置を調べる鍵（外のクリック判定用）。
  final Map<String, GlobalKey> _volumeBoxKeys = {};
  final Map<String, GlobalKey> _volumeButtonKeys = {};
  bool _watchingPointers = false;

  /// スライダーを開いている間だけ、画面のどこかのクリックを見張る（2026-11-16）。スライダーと
  /// 音量ボタンの外を押したら閉じる。ポインターを横取りせず見るだけなので、押した先の操作
  /// （ピン留め・拡縮など）もそのまま効く。
  void _syncPointerWatch() {
    final want = _volumeOpen.isNotEmpty;
    if (want == _watchingPointers) return;
    _watchingPointers = want;
    final router = GestureBinding.instance.pointerRouter;
    if (want) {
      router.addGlobalRoute(_onGlobalPointer);
    } else {
      router.removeGlobalRoute(_onGlobalPointer);
    }
  }

  bool _hits(GlobalKey? key, Offset position) {
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(position);
  }

  void _onGlobalPointer(PointerEvent event) {
    if (event is! PointerDownEvent || !mounted) return;
    final outside = [
      for (final key in _volumeOpen)
        if (!_hits(_volumeBoxKeys[key], event.position) &&
            !_hits(_volumeButtonKeys[key], event.position))
          key,
    ];
    if (outside.isEmpty) return;
    setState(() => _volumeOpen.removeAll(outside));
    _syncPointerWatch();
  }

  @override
  void dispose() {
    if (_watchingPointers) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    }
    super.dispose();
  }

  GlobalKey _keyFor(String key) => _keys.putIfAbsent(key, GlobalKey.new);

  Widget _window(CallTileSpec spec, bool pinned, bool isPinned) {
    final strings = ref.watch(appStringsProvider);
    return KeyedSubtree(
      key: _keyFor(spec.key),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            // ピンチ・ホイールで拡縮できる（最大化のビューアの代わり、2026-11-16）。ピン留めを
            // 切り替えたら等倍に戻る。
            CallZoomable(resetKey: isPinned, child: spec.build(pinned)),
            if (spec.volume != null)
              ..._volumeControls(spec, constraints.maxHeight),
            Positioned(
              top: 6,
              left: 6,
              child: PointerInterceptor(
                child: Tooltip(
                  message: isPinned
                      ? strings.callUnpinWindow
                      : strings.callPinWindow,
                  child: GestureDetector(
                    key: ValueKey('pin-${spec.key}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => ref
                        .read(callPinnedTilesProvider.notifier)
                        .toggle(spec.key),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Icon(
                          isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 右下の音量ボタンと、開いている時のスライダー（2026-11-16）。
  List<Widget> _volumeControls(CallTileSpec spec, double tileHeight) {
    final sliderHeight = (tileHeight - 64).clamp(80.0, 150.0);
    final volume = spec.volume!;
    final strings = ref.watch(appStringsProvider);
    final open = _volumeOpen.contains(spec.key);
    return [
      if (open)
        Positioned(
          right: 6,
          bottom: 48,
          // 小さいウィンドウ（ピン留め時の下の帯）では、収まる高さに縮める。
          child: PointerInterceptor(
            child: DecoratedBox(
              key: _volumeBoxKeys.putIfAbsent(spec.key, GlobalKey.new),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              // `Slider`はMaterialの祖先が要る（PCの通話画面はScaffoldの外に出る）。
              // 縦にする（下が最小・上が最大）。
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  width: 40,
                  height: sliderHeight,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Slider(
                      key: ValueKey('volume-slider-${spec.key}'),
                      value: volume.value.clamp(0.0, 1.0),
                      onChanged: volume.onChanged,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      Positioned(
        right: 6,
        bottom: 6,
        child: PointerInterceptor(
          child: Tooltip(
            message: strings.callVolume,
            child: GestureDetector(
              key: ValueKey('volume-${spec.key}'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  if (!_volumeOpen.remove(spec.key)) _volumeOpen.add(spec.key);
                });
                _syncPointerWatch();
              },
              child: DecoratedBox(
                key: _volumeButtonKeys.putIfAbsent(spec.key, GlobalKey.new),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Icon(
                    volume.value <= 0 ? Icons.volume_off : Icons.volume_up,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// [windows]を[callTileRowSizes]の行構成で、与えられた領域いっぱいに並べる。
  Widget _rows(List<Widget> windows) {
    final spacing = widget.spacing;
    return LayoutBuilder(
      builder: (context, constraints) {
        final portrait = constraints.maxHeight > constraints.maxWidth;
        final sizes = callTileRowSizes(windows.length, portrait: portrait);
        if (sizes == null) return const SizedBox.shrink();
        final maxPerRow = sizes.reduce(math.max);
        // 横長で枚数が少ない行は、最大の行と同じ幅で中央に寄せる（縦長は行いっぱい）。
        final tileWidth =
            (constraints.maxWidth - spacing * (maxPerRow + 1)) / maxPerRow;
        var index = 0;
        return Padding(
          padding: EdgeInsets.all(spacing),
          child: Column(
            children: [
              for (var r = 0; r < sizes.length; r++) ...[
                if (r > 0) SizedBox(height: spacing),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var c = 0; c < sizes[r]; c++) ...[
                        if (c > 0) SizedBox(width: spacing),
                        if (portrait)
                          Expanded(child: windows[index++])
                        else
                          SizedBox(width: tileWidth, child: windows[index++]),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// ピンしていないウィンドウを並べる、細い1行の帯。多い時は横にスクロールする。
  Widget _strip(List<Widget> windows) {
    final spacing = widget.spacing;
    return LayoutBuilder(
      builder: (context, constraints) {
        const minWidth = 110.0;
        final fit =
            (constraints.maxWidth - spacing * (windows.length + 1)) /
            windows.length;
        return Padding(
          padding: EdgeInsets.fromLTRB(spacing, 0, spacing, spacing),
          child: fit >= minWidth
              ? Row(
                  children: [
                    for (var i = 0; i < windows.length; i++) ...[
                      if (i > 0) SizedBox(width: spacing),
                      Expanded(child: windows[i]),
                    ],
                  ],
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: windows.length,
                  separatorBuilder: (_, _) => SizedBox(width: spacing),
                  itemBuilder: (_, i) =>
                      SizedBox(width: minWidth, child: windows[i]),
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final specs = widget.specs;
    final keys = {for (final s in specs) s.key};
    _keys.removeWhere((k, _) => !keys.contains(k));
    final stored = ref.watch(callPinnedTilesProvider);
    final pinnedKeys = stored.where(keys.contains).toSet();
    // 無くなったウィンドウ（共有の終了・退出）のピンは外す。
    if (pinnedKeys.length != stored.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(callPinnedTilesProvider.notifier).retain(keys);
        }
      });
    }
    final pinned = [
      for (final s in specs)
        if (pinnedKeys.contains(s.key)) s,
    ];
    final rest = [
      for (final s in specs)
        if (!pinnedKeys.contains(s.key)) s,
    ];

    if (pinned.isEmpty || rest.isEmpty) {
      return _rows([
        for (final s in specs)
          _window(s, pinned.isNotEmpty, pinnedKeys.contains(s.key)),
      ]);
    }
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: _rows([for (final s in pinned) _window(s, true, true)]),
        ),
        Expanded(
          flex: 1,
          child: _strip([for (final s in rest) _window(s, false, false)]),
        ),
      ],
    );
  }
}

/// 1対1の映像の収め方（2026-10-30）。メイン映像は、領域が縦長（高さ>幅）なら
/// 画面いっぱいに切り抜いて（Cover）埋め、横長なら全体を見せる（Contain、余白は
/// 灰色）。縦長の画面に、相手のPCカメラのような横長の映像をContainで入れると、
/// 中央に横長の帯だけが映り上下が空くため。コーナーの小窓は常にCover。
RTCVideoViewObjectFit callVideoFitFor({
  required bool portraitArea,
  required bool main,
}) => (main && !portraitArea)
    ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
    : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover;

/// 発声中の参加者のタイルを囲む枠（2026-10-31）。色はアクセントカラー（2026-11-15、以前は緑）。
/// タップは下のタイルへ通す。
const kCallTileRadius = 12.0;

class SpeakingFrame extends StatelessWidget {
  const SpeakingFrame({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kCallTileRadius),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 4,
        ),
      ),
    ),
  );
}

/// 名前・ミュートなどのラベルの下に敷く黒の半透明のシート（2026-10-31、映像の上でも
/// 読めるようにする）。影は使わない。
class CallLabelSheet extends StatelessWidget {
  const CallLabelSheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: child,
    ),
  );
}

/// 画面共有（配信）のタイル（2026-11-15）。映像（切り抜かず全体を見せる）、左下に
/// 「モニターのアイコン＋名前」、右上に赤い「ライブ」と画質の表示（Discordの配信と同じ配置）。
class ScreenShareFrame extends StatelessWidget {
  const ScreenShareFrame({
    required this.video,
    required this.name,
    required this.qualityLabel,
    required this.liveText,
    super.key,
  });

  /// 映像（`RTCVideoView`。`objectFit`はContain）。
  final Widget video;

  /// 配信している人の呼び名（文字は白）。
  final Widget name;
  final String qualityLabel;
  final String liveText;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCallTileRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black, child: video),
          Positioned(
            left: 8,
            bottom: 8,
            child: IgnorePointer(
              child: CallLabelSheet(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.desktop_windows_outlined,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    name,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      // 濃い赤に白（明るい色に白文字は禁止）。
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        liveText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CallLabelSheet(
                    child: Text(
                      qualityLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 参加者の映像（2026-11-16）。映像が縦長（高さ>幅）なら、ウィンドウが横長でも切り抜かず、
/// 左右に黒帯を付けて縦のまま全体を見せる。横長・正方形は、[fullFit]（ピン留め中）なら全体、
/// そうでなければ枠いっぱいに切り抜く。余白は黒。向きが変わったら（端末を回した時など）
/// 自動で切り替わる。
class CallPersonVideo extends StatelessWidget {
  const CallPersonVideo({
    required this.renderer,
    required this.fullFit,
    this.mirror = false,
    super.key,
  });

  final RTCVideoRenderer renderer;
  final bool fullFit;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RTCVideoValue>(
      valueListenable: renderer,
      builder: (context, value, _) {
        final portrait = isPortraitVideo(value);
        return ColoredBox(
          color: Colors.black,
          child: RTCVideoView(
            // Web版のRTCVideoViewは実描画の要素をinitStateでしか取得しないため、
            // レンダラー自体をキーにする。
            key: ValueKey(renderer),
            renderer,
            mirror: mirror,
            objectFit: (fullFit || portrait)
                ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        );
      },
    );
  }
}

/// 映像が縦長か。大きさがまだ分からない間（0）は`false`。回転（90・270度）は反映済み。
bool isPortraitVideo(RTCVideoValue value) =>
    value.width > 0 && value.height > 0 && value.aspectRatio < 1.0;

/// ウィンドウの中身をピンチ・マウスホイールで拡縮する（2026-11-16）。1〜[maxScale]倍。
/// 拡大中はドラッグで動かせ、ダブルタップ（ダブルクリック）で等倍に戻る。[resetKey]が変わると
/// 等倍に戻る（ピン留めを切り替えた時）。通話画面にスクロールは無く、等倍のドラッグは何もしない。
/// Webの映像は描画要素がポインターを奪うため、`PointerInterceptor`で覆って受け取る。
class CallZoomable extends StatefulWidget {
  const CallZoomable({
    required this.child,
    this.resetKey,
    this.maxScale = 5.0,
    super.key,
  });

  final Widget child;
  final Object? resetKey;
  final double maxScale;

  @override
  State<CallZoomable> createState() => _CallZoomableState();
}

class _CallZoomableState extends State<CallZoomable> {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  Size _size = Size.zero;

  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  @override
  void didUpdateWidget(CallZoomable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) _reset();
  }

  void _reset() {
    if (_scale == 1.0 && _offset == Offset.zero) return;
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  /// [focal]（ウィンドウ内の座標）の下にある点を動かさずに、倍率を[scale]へ変える。
  void _zoomAt(
    Offset focal,
    double scale, {
    required double fromScale,
    required Offset fromOffset,
    required Offset toFocal,
  }) {
    final next = scale.clamp(1.0, widget.maxScale);
    final scenePoint = (focal - fromOffset) / fromScale;
    var offset = toFocal - scenePoint * next;
    // 映像が枠の外へ出きらないように抑える。
    final minX = _size.width - _size.width * next;
    final minY = _size.height - _size.height * next;
    offset = Offset(offset.dx.clamp(minX, 0.0), offset.dy.clamp(minY, 0.0));
    setState(() {
      _scale = next;
      _offset = next <= 1.0 ? Offset.zero : offset;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform(
                transform: Matrix4.identity()
                  ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                  ..scaleByDouble(_scale, _scale, 1, 1),
                child: widget.child,
              ),
              Positioned.fill(
                child: PointerInterceptor(
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is! PointerScrollEvent) return;
                      _zoomAt(
                        event.localPosition,
                        _scale * math.exp(-event.scrollDelta.dy / 300),
                        fromScale: _scale,
                        fromOffset: _offset,
                        toFocal: event.localPosition,
                      );
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _reset,
                      onScaleStart: (d) {
                        _startScale = _scale;
                        _startOffset = _offset;
                        _startFocal = d.localFocalPoint;
                      },
                      onScaleUpdate: (d) => _zoomAt(
                        _startFocal,
                        _startScale * d.scale,
                        fromScale: _startScale,
                        fromOffset: _startOffset,
                        toFocal: d.localFocalPoint,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
