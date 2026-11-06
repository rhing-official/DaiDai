import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/audio_playback_provider.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/glass/glass_surface.dart';

/// 音声添付を再生している間、語らい上部（予定などのバナーのさらに下）に出すバナー
/// （2026-11-02）。再生している音声のファイル名と、一時停止／再開・停止のボタンを持つ。
/// 再生は`audioPlaybackProvider`が持つため、元のメッセージがスクロールで画面から外れても
/// ここから操作出来る。10秒戻す・10秒送るのボタンも持つ（2026-11-05）。再生していない時は何も出さない。見た目は`GroupCallJoinBanner`・
/// `ChatTaskBanner`と同じ（劇画は白黒、フラット・ガラスはアクセントカラー）。
class AudioPlaybackBanner extends ConsumerWidget {
  const AudioPlaybackBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(audioPlaybackProvider);
    if (!playback.active) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final background = isGekiga ? GekigaColors.panel : colorScheme.primary;
    final foreground = isGekiga ? GekigaColors.onPanel : colorScheme.onPrimary;
    final notifier = ref.read(audioPlaybackProvider.notifier);
    final duration = playback.duration;
    final durationMs = duration?.inMilliseconds.toDouble();
    final sliderMax = (durationMs == null || durationMs <= 0)
        ? 1.0
        : durationMs;
    final sliderValue = playback.position.inMilliseconds.toDouble().clamp(
      0.0,
      sliderMax,
    );

    final content = Padding(
      padding: const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.graphic_eq, size: 18, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playback.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: foreground),
                ),
                // 丸（つまみ）をドラッグ・タップして、再生位置を飛ばせる。
                SizedBox(
                  height: 20,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: foreground,
                      inactiveTrackColor: foreground.withValues(alpha: 0.3),
                      thumbColor: foreground,
                      trackShape: const RoundedRectSliderTrackShape(),
                    ),
                    child: Slider(
                      min: 0,
                      max: sliderMax,
                      value: sliderValue,
                      onChanged: durationMs == null
                          ? null
                          : (v) => notifier.seek(
                              Duration(milliseconds: v.round()),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.replay_10, size: 22, color: foreground),
            onPressed: () => notifier.skip(const Duration(seconds: -10)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              playback.playing ? Icons.pause : Icons.play_arrow,
              size: 22,
              color: foreground,
            ),
            onPressed: playback.playing ? notifier.pause : notifier.resume,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.forward_10, size: 22, color: foreground),
            onPressed: () => notifier.skip(const Duration(seconds: 10)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.stop, size: 22, color: foreground),
            onPressed: notifier.stop,
          ),
        ],
      ),
    );

    if (isGlass) {
      return GlassSurface(
        variant: GlassVariant.chrome,
        borderRadius: BorderRadius.zero,
        enableEdgeStroke: false,
        child: Material(
          color: background.withValues(alpha: 0.55),
          child: content,
        ),
      );
    }
    final borderColor = isGekiga
        ? GekigaColors.onPanel
        : colorScheme.outlineVariant;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: isGekiga ? 3 : 1),
      ),
      child: Material(color: background, child: content),
    );
  }
}
