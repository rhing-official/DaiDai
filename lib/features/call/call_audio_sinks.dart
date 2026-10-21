import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// 映像を画面に出していない参加者の音声を、鳴らすための「見えない動画要素」
/// （2026-10-21追加）。Webでは、リモートの音声は`RTCVideoView`（`<video>`要素）に
/// 紐づいて再生されるため、映像オフの参加者のタイルが`RTCVideoView`を持たないと、
/// その人の音声が聞こえない（広場通話で、自分の映像は見えるが他人の音声が聞こえない
/// 不具合の原因）。大きさ0×0だとモバイルのブラウザが再生しないことがあるため、
/// 1×1・ほぼ透明にしている。操作は受けない。
///
/// 映像を表示している参加者のレンダラーは渡さないこと（その`RTCVideoView`が既に
/// 音を鳴らすため、二重に再生されてしまう）。
class CallAudioSinks extends StatelessWidget {
  const CallAudioSinks({required this.renderers, super.key});

  final List<RTCVideoRenderer> renderers;

  @override
  Widget build(BuildContext context) {
    if (renderers.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox(
        width: 1,
        height: 1,
        child: Opacity(
          opacity: 0.01,
          child: Stack(
            children: [
              for (final renderer in renderers)
                RTCVideoView(key: ObjectKey(renderer), renderer),
            ],
          ),
        ),
      ),
    );
  }
}

/// 音声だけを鳴らす（映像のタイルを画面に出していない）リモート参加者のid
/// （2026-10-21追加）。[videoOnIds]の参加者は、グリッド表示ならそのタイルの
/// `RTCVideoView`が音を鳴らす。1人を拡大表示している間（[focusedUserId]）は、
/// 拡大している映像の参加者だけがタイルを持つため、他の参加者は音声だけを鳴らす。
/// [focusedUserId]が自分や存在しないidなら、リモート全員が対象になる。
List<String> groupAudioOnlyUserIds({
  required List<String> remoteIds,
  required Set<String> videoOnIds,
  String? focusedUserId,
}) {
  return [
    for (final id in remoteIds)
      if (!(videoOnIds.contains(id) &&
          (focusedUserId == null || focusedUserId == id)))
        id,
  ];
}
