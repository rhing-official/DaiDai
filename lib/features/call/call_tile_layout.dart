import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCVideoViewObjectFit;
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../l10n/strings.dart';
import 'call_pin_provider.dart';

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
  const CallTileSpec({required this.key, required this.build, this.onTap});

  final String key;

  /// ウィンドウの中身。[pinned]は、ピン留めされて大きく出している時（アイコンの大きさ・
  /// 映像の収め方を変える）。
  final Widget Function(bool pinned) build;

  /// タップ（映像の拡大ビューアを開く）。映像が無いウィンドウは`null`。
  final VoidCallback? onTap;
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

  GlobalKey _keyFor(String key) => _keys.putIfAbsent(key, GlobalKey.new);

  Widget _window(CallTileSpec spec, bool pinned, bool isPinned) {
    final strings = ref.watch(appStringsProvider);
    return KeyedSubtree(
      key: _keyFor(spec.key),
      child: Stack(
        fit: StackFit.expand,
        children: [
          spec.build(pinned),
          if (spec.onTap != null)
            Positioned.fill(
              child: PointerInterceptor(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: spec.onTap,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
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
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                        size: 16,
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
    );
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
