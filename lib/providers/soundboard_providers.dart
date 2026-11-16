import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/soundboard_sound.dart';
import 'repository_providers.dart';

/// 会話（広場・一対）のサウンドボードの効果音の一覧。
final soundboardSoundsProvider =
    StreamProvider.family<
      List<SoundboardSound>,
      ({bool isDm, String conversationId})
    >((ref, key) {
      return ref
          .watch(soundboardRepositoryProvider)
          .watchSounds(isDm: key.isDm, conversationId: key.conversationId);
    });

/// サウンドボードの音量（0〜1）。この端末のこの起動中だけ覚える。
class SoundboardVolumeNotifier extends Notifier<double> {
  @override
  double build() => 0.7;

  void set(double value) => state = value;
}

final soundboardVolumeProvider =
    NotifierProvider<SoundboardVolumeNotifier, double>(
      SoundboardVolumeNotifier.new,
    );
