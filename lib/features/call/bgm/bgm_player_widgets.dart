import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/app_ui_style.dart';
import '../../../providers/app_ui_style_provider.dart';
import '../../../l10n/strings.dart';
import 'bgm_now_playing.dart';
import 'bgm_queue.dart';
import 'bgm_track.dart';
import 'call_bgm.dart';
import 'call_bgm_sheet.dart' show CallPanelSurface;

/// 曲のジャケット画像（無ければ音符）。シートの曲一覧・再生中の表示・ミニプレーヤーで共通。
class BgmCoverImage extends StatelessWidget {
  const BgmCoverImage({
    required this.bgm,
    required this.track,
    required this.size,
    super.key,
  });

  final CallBgm bgm;
  final BgmTrack track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(size > 60 ? 12 : 6);
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.08),
        borderRadius: radius,
      ),
      child: Icon(
        Icons.music_note,
        size: size * 0.5,
        color: scheme.onSurface.withValues(alpha: 0.6),
      ),
    );
    if (!track.hasCover) return placeholder;
    return FutureBuilder<Uint8List?>(
      future: bgm.coverOf(track),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return placeholder;
        return ClipRRect(
          borderRadius: radius,
          child: Image.memory(
            data,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => placeholder,
          ),
        );
      },
    );
  }
}

String formatBgmDuration(Duration d) {
  final total = d.inSeconds;
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 再生位置のバー（ドラッグで移動）と、「1:23 / 3:45」の時間。
class BgmSeekBar extends StatefulWidget {
  const BgmSeekBar({required this.bgm, super.key});

  final CallBgm bgm;

  @override
  State<BgmSeekBar> createState() => _BgmSeekBarState();
}

class _BgmSeekBarState extends State<BgmSeekBar> {
  /// ドラッグ中の位置（0〜1）。nullの間は、再生位置に従う。
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall;
    return ValueListenableBuilder<BgmProgress>(
      valueListenable: widget.bgm.progress,
      builder: (context, progress, _) {
        final duration = progress.duration;
        final total = duration?.inMilliseconds ?? 0;
        final ratio = total <= 0
            ? 0.0
            : (progress.position.inMilliseconds / total).clamp(0.0, 1.0);
        final shown = _dragging ?? ratio;
        final shownPosition = duration == null
            ? progress.position
            : Duration(milliseconds: (shown * total).round());
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: shown,
                onChanged: duration == null
                    ? null
                    : (v) => setState(() => _dragging = v),
                onChangeEnd: duration == null
                    ? null
                    : (v) {
                        widget.bgm.seek(
                          Duration(milliseconds: (v * total).round()),
                        );
                        setState(() => _dragging = null);
                      },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatBgmDuration(shownPosition), style: textStyle),
                  Text(
                    duration == null ? '--:--' : formatBgmDuration(duration),
                    style: textStyle,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 前の曲・再生/一時停止・次の曲のボタン。[full]なら、停止と再生順も並べる。
class BgmTransportControls extends StatelessWidget {
  const BgmTransportControls({
    required this.bgm,
    required this.strings,
    this.full = false,
    super.key,
  });

  final CallBgm bgm;
  final Strings strings;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final iconSize = full ? 32.0 : 24.0;
    final (orderIcon, orderLabel) = switch (bgm.playOrder) {
      BgmPlayOrder.inOrder => (Icons.repeat, strings.callBgmOrderInOrder),
      BgmPlayOrder.inOrderNextAlbum => (
        Icons.queue_music,
        strings.callBgmOrderNextAlbum,
      ),
      BgmPlayOrder.shuffle => (Icons.shuffle, strings.callBgmOrderShuffle),
      BgmPlayOrder.repeatOne => (
        Icons.repeat_one,
        strings.callBgmOrderRepeatOne,
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (full)
          IconButton(
            tooltip: orderLabel,
            icon: Icon(orderIcon),
            onPressed: bgm.cyclePlayOrder,
          ),
        if (full)
          IconButton(
            tooltip: strings.callBgmRewind10,
            icon: const Icon(Icons.replay_10),
            onPressed: () => bgm.skipBy(const Duration(seconds: -10)),
          ),
        IconButton(
          tooltip: strings.callBgmPrevious,
          iconSize: iconSize,
          icon: const Icon(Icons.skip_previous),
          onPressed: bgm.playPrevious,
        ),
        IconButton(
          tooltip: bgm.paused ? strings.callBgmResume : strings.callBgmPause,
          iconSize: iconSize + (full ? 8 : 0),
          icon: Icon(
            bgm.paused ? Icons.play_circle_filled : Icons.pause_circle_filled,
          ),
          onPressed: bgm.togglePause,
        ),
        IconButton(
          tooltip: strings.callBgmNext,
          iconSize: iconSize,
          icon: const Icon(Icons.skip_next),
          onPressed: bgm.playNext,
        ),
        if (full)
          IconButton(
            tooltip: strings.callBgmForward10,
            icon: const Icon(Icons.forward_10),
            onPressed: () => bgm.skipBy(const Duration(seconds: 10)),
          ),
        if (full)
          IconButton(
            tooltip: strings.callBgmStop,
            icon: const Icon(Icons.stop),
            onPressed: bgm.stop,
          ),
        if (full && bgm.current != null)
          BgmFavoriteButton(bgm: bgm, track: bgm.current!, strings: strings),
      ],
    );
  }
}

/// 通話画面の、再生中のミニプレーヤー（曲名・前へ・一時停止・次へ）。流していない間は何も出さない。
/// 曲名の部分を押すと、BGMのシートを開く。
class BgmMiniPlayer extends StatelessWidget {
  const BgmMiniPlayer({
    required this.bgm,
    required this.strings,
    required this.onOpen,
    super.key,
  });

  final CallBgm bgm;
  final Strings strings;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: bgm,
      builder: (context, _) {
        final track = bgm.current;
        if (track == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: BgmSpaceKeyToggle(
            bgm: bgm,
            child: _MiniPlayerSurface(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: onOpen,
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BgmCoverImage(bgm: bgm, track: track, size: 36),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: Text(
                              track.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurface),
                            ),
                          ),
                        ],
                      ),
                    ),
                    BgmTransportControls(bgm: bgm, strings: strings),
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

/// 相手が流している曲の、細いプレーヤー（ジャケット・曲名・前へ・一時停止・次へ）。表示のみで、押しても何も起きない。
class BgmRemoteMiniPlayer extends StatelessWidget {
  const BgmRemoteMiniPlayer({required this.nowPlaying, super.key});

  final BgmNowPlaying nowPlaying;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final thumb = nowPlaying.thumb;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _MiniPlayerSurface(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: thumb == null
                      ? ColoredBox(
                          color: scheme.onSurface.withValues(alpha: 0.08),
                          child: Icon(Icons.music_note, size: 18, color: muted),
                        )
                      : Image.memory(
                          thumb,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) =>
                              Icon(Icons.music_note, size: 18, color: muted),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  nowPlaying.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurface),
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.skip_previous, color: scheme.onSurface),
              const SizedBox(width: 8),
              Icon(
                nowPlaying.paused ? Icons.play_circle : Icons.pause_circle,
                size: 32,
                color: scheme.onSurface,
              ),
              const SizedBox(width: 8),
              Icon(Icons.skip_next, color: scheme.onSurface),
            ],
          ),
        ),
      ),
    );
  }
}

/// 曲のお気に入りの印（★）。押すと、付ける／外す。
class BgmFavoriteButton extends StatelessWidget {
  const BgmFavoriteButton({
    required this.bgm,
    required this.track,
    required this.strings,
    super.key,
  });

  final CallBgm bgm;
  final BgmTrack track;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final fav = bgm.isFavorite(track);
    return IconButton(
      tooltip: fav ? strings.callBgmFavoriteRemove : strings.callBgmFavoriteAdd,
      icon: Icon(fav ? Icons.star : Icons.star_border),
      onPressed: () => bgm.toggleFavorite(track),
    );
  }
}

/// ミニプレーヤーの面。劇画・ガラス・版画は、BGMのシートと同じ`CallPanelSurface`（各スタイルの面）にし、
/// フラットは従来の丸い半透明の面にする。
class _MiniPlayerSurface extends ConsumerWidget {
  const _MiniPlayerSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appUiStyleProvider);
    if (style == AppUiStyle.gekiga ||
        style == AppUiStyle.glass ||
        style.isBoxed) {
      return CallPanelSurface(allRounded: true, child: child);
    }
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 表示している間、スペースキーで曲の再生・一時停止を切り替える（BGMのシート・ミニプレーヤー用）。
/// 文字入力中は何もしない。複数が同時に表示されても、1回の押下で1回だけ切り替える。
class BgmSpaceKeyToggle extends StatefulWidget {
  const BgmSpaceKeyToggle({required this.bgm, required this.child, super.key});

  final CallBgm bgm;
  final Widget child;

  @override
  State<BgmSpaceKeyToggle> createState() => _BgmSpaceKeyToggleState();
}

class _BgmSpaceKeyToggleState extends State<BgmSpaceKeyToggle> {
  static final _active = <_BgmSpaceKeyToggleState>[];

  @override
  void initState() {
    super.initState();
    if (_active.isEmpty) HardwareKeyboard.instance.addHandler(_onKey);
    _active.add(this);
  }

  @override
  void dispose() {
    _active.remove(this);
    if (_active.isEmpty) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  static bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.space ||
        _active.isEmpty) {
      return false;
    }
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (focus.widget is EditableText ||
            focus.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    final bgm = _active.last.widget.bgm;
    if (bgm.current == null) return false;
    bgm.togglePause();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
