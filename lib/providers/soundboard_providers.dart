import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/soundboard_sound.dart';
import 'group_providers.dart';
import 'repository_providers.dart';

/// 会話（広場・一対）に登録されている効果音（追加した語らいに置かれた参照と、以前の
/// 語らい単位の音）。画面には[soundboardListsProvider]で合成した一覧を使う。
final soundboardSoundsProvider =
    StreamProvider.family<
      List<SoundboardSound>,
      ({bool isDm, String conversationId})
    >((ref, key) {
      return ref
          .watch(soundboardRepositoryProvider)
          .watchSounds(isDm: key.isDm, conversationId: key.conversationId);
    });

/// [userId]が追加した効果音（個人保存。どの語らいでも使える、2026-11-17）。
final mySoundboardSoundsProvider =
    StreamProvider.family<List<SoundboardSound>, String>((ref, userId) {
      return ref.watch(soundboardRepositoryProvider).watchMySounds(userId);
    });

/// 語らいのサウンドボードに出す効果音（マイサウンドと、この語らいの他の人の音）。
/// 広場では、追加した人が今のメンバーでない音は出さない。
final soundboardListsProvider =
    Provider.family<
      SoundboardLists,
      ({bool isDm, String conversationId, String userId})
    >((ref, key) {
      final mine =
          ref.watch(mySoundboardSoundsProvider(key.userId)).value ?? const [];
      final inConversation =
          ref
              .watch(
                soundboardSoundsProvider((
                  isDm: key.isDm,
                  conversationId: key.conversationId,
                )),
              )
              .value ??
          const [];
      final members = key.isDm
          ? null
          : ref
                .watch(watchedGroupProvider(key.conversationId))
                .value
                ?.memberIds
                .toSet();
      return composeSoundboardSounds(
        userId: key.userId,
        mine: mine,
        inConversation: inConversation,
        memberIds: members,
      );
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
