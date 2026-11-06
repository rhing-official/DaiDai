import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/strings.dart';
import 'bgm_track.dart';
import 'call_bgm.dart';

/// 通話のBGMの操作に必要なものをまとめた束（2026-11-03）。通話画面のボタン列
/// （`CallControlBar`）へ、1対1・広場のコントローラーの違いを隠して渡す。
class CallBgmBinding {
  const CallBgmBinding({
    required this.bgm,
    required this.controller,
    required this.otherPlayingTitle,
  });

  final CallBgm bgm;

  /// 通話コントローラー（相手のBGMの状態が変わったらシートを描き直す）。
  final Listenable controller;

  /// 他の人が流している曲名（いなければnull）。
  final String? Function() otherPlayingTitle;
}

/// 拡張子から音声のMIMEタイプを決める（`<audio>`が形式を判別出来るように）。
String bgmMimeTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'mp3' => 'audio/mpeg',
    'm4a' || 'mp4' || 'aac' => 'audio/mp4',
    'wav' => 'audio/wav',
    'ogg' || 'oga' || 'opus' => 'audio/ogg',
    'flac' => 'audio/flac',
    'webm' => 'audio/webm',
    _ => 'audio/mpeg',
  };
}

/// 拡張子を除いた表示名。
String bgmDisplayName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

Future<void> showCallBgmSheet(BuildContext context, CallBgmBinding binding) {
  binding.bgm.loadTracks();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _CallBgmSheet(binding: binding),
  );
}

class _CallBgmSheet extends ConsumerWidget {
  const _CallBgmSheet({required this.binding});

  final CallBgmBinding binding;

  Future<void> _add(BuildContext context, Strings strings) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final file = await FilePicker.pickFile(type: FileType.audio);
      if (file == null) return;
      await binding.bgm.addTrack(
        name: bgmDisplayName(file.name),
        mimeType: bgmMimeTypeFor(file.name),
        bytes: await file.readAsBytes(),
      );
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(strings.callBgmAddFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final bgm = binding.bgm;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          maxWidth: 560,
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([bgm, binding.controller]),
          builder: (context, _) {
            final other = binding.otherPlayingTitle();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.callBgmTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (other != null) ...[
                    const SizedBox(height: 8),
                    Text(strings.callBgmOtherPlaying(other)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(strings.callBgmVolume),
                      Expanded(
                        child: Slider(
                          value: bgm.volume,
                          onChanged: bgm.setVolume,
                        ),
                      ),
                    ],
                  ),
                  Flexible(
                    child: bgm.tracks.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(strings.callBgmEmpty),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final track in bgm.tracks)
                                _TrackTile(
                                  track: track,
                                  playing: bgm.current?.id == track.id,
                                  strings: strings,
                                  onPlay: () => bgm.play(track),
                                  onStop: bgm.stop,
                                  onRemove: () => bgm.removeTrack(track),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _add(context, strings),
                    icon: const Icon(Icons.add),
                    label: Text(strings.callBgmAdd),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.playing,
    required this.strings,
    required this.onPlay,
    required this.onStop,
    required this.onRemove,
  });

  final BgmTrack track;
  final bool playing;
  final Strings strings;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      leading: IconButton(
        tooltip: playing ? strings.callBgmStop : null,
        icon: Icon(
          playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
        ),
        onPressed: playing ? onStop : onPlay,
      ),
      trailing: IconButton(
        tooltip: strings.callBgmRemove,
        icon: const Icon(Icons.delete_outline),
        onPressed: onRemove,
      ),
    );
  }
}
