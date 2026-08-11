import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'call_sounds.dart';

/// 通話中の効果音（着信音・入退室ブリップ）再生をまとめる。
/// 用途ごとに専用の`AudioPlayer`を持つことで、同時に発生しても
/// （例: 入室直後に別の人が退室）互いの再生を打ち切らないようにする。
class CallSoundPlayer {
  final _ringtonePlayer = AudioPlayer();
  final _joinPlayer = AudioPlayer();
  final _leavePlayer = AudioPlayer();

  Future<void> startRingtoneLoop() async {
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.play(AssetSource(CallSound.ringtone.assetPath));
    } catch (_) {
      // Web等、ユーザー操作前の自動再生がブロックされる環境がある。無視して継続。
    }
  }

  Future<void> stopRingtone() => _ringtonePlayer.stop();

  StreamSubscription<void>? _ringtoneTimesSub;

  /// 広場（グループ）通話の着信バナー用: ループ再生ではなく、指定回数
  /// （3コール）だけ鳴らして自動的に止める。
  Future<void> playRingtoneTimes(int times) async {
    if (times <= 0) return;
    try {
      await _ringtoneTimesSub?.cancel();
      await _ringtonePlayer.setReleaseMode(ReleaseMode.stop);
      var remaining = times - 1;
      _ringtoneTimesSub = _ringtonePlayer.onPlayerComplete.listen((_) async {
        if (remaining <= 0) {
          await _ringtoneTimesSub?.cancel();
          _ringtoneTimesSub = null;
          return;
        }
        remaining--;
        await _ringtonePlayer.play(AssetSource(CallSound.ringtone.assetPath));
      });
      await _ringtonePlayer.play(AssetSource(CallSound.ringtone.assetPath));
    } catch (_) {
      // Web等、ユーザー操作前の自動再生がブロックされる環境がある。無視して継続。
    }
  }

  Future<void> playJoinBlip() async {
    try {
      await _joinPlayer.play(
        AssetSource(CallSound.participantJoined.assetPath),
      );
    } catch (_) {
      // 再生できない環境でも通話自体は継続させる。
    }
  }

  Future<void> playLeaveBlip() async {
    try {
      await _leavePlayer.play(AssetSource(CallSound.participantLeft.assetPath));
    } catch (_) {
      // 再生できない環境でも通話自体は継続させる。
    }
  }

  Future<void> dispose() async {
    await _ringtoneTimesSub?.cancel();
    await _ringtonePlayer.dispose();
    await _joinPlayer.dispose();
    await _leavePlayer.dispose();
  }
}
