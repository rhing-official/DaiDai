import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'call_sounds.dart';

/// 通話中の効果音（着信音・呼出音・入退室ブリップ）再生をまとめる。
/// 用途ごとに専用の`AudioPlayer`を持つことで、同時に発生しても
/// （例: 入室直後に別の人が退室）互いの再生を打ち切らないようにする。
class CallSoundPlayer {
  final _ringtonePlayer = AudioPlayer();
  final _callingPlayer = AudioPlayer();
  final _joinPlayer = AudioPlayer();
  final _leavePlayer = AudioPlayer();
  final _previewPlayer = AudioPlayer();

  /// [source]は`sound_preset.dart`の`SoundCategoryPresets.resolveSource`で
  /// 解決した値（`http`で始まればカスタムアップロード音源のURL、それ以外は
  /// `AssetSource`用の相対パス）。着信側（発信者ではない方）が呼ぶ
  /// （2026-09-06、ユーザーごとのカスタム着信音対応で`source`引数を追加）。
  Future<void> startRingtoneLoop(String source) async {
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.play(_sourceFor(source));
    } catch (_) {
      // Web等、ユーザー操作前の自動再生がブロックされる環境がある。無視して継続。
    }
  }

  /// 呼出音（発信者が相手の応答を待つ間に聞く音、2026-09-06新設）。
  Future<void> startCallingLoop(String source) async {
    try {
      await _callingPlayer.setReleaseMode(ReleaseMode.loop);
      await _callingPlayer.play(_sourceFor(source));
    } catch (_) {
      // Web等、ユーザー操作前の自動再生がブロックされる環境がある。無視して継続。
    }
  }

  /// 通話終了時に呼ぶ。発信者/着信者どちらの終了時も一律で呼ばれるため
  /// （`ActiveCallSessionNotifier._teardown`参照）、着信音・呼出音の両方の
  /// ループをまとめて止める。
  Future<void> stopRingtone() =>
      Future.wait([_ringtonePlayer.stop(), _callingPlayer.stop()]);

  StreamSubscription<void>? _ringtoneTimesSub;

  /// 広場（グループ）通話の着信バナー用: ループ再生ではなく、指定回数
  /// （3コール）だけ鳴らして自動的に止める。
  Future<void> playRingtoneTimes(int times, String source) async {
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
        await _ringtonePlayer.play(_sourceFor(source));
      });
      await _ringtonePlayer.play(_sourceFor(source));
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

  /// 設定画面での試聴用（ワンショット再生、2026-09-06追加）。
  Future<void> playPreview(String source) async {
    try {
      await _previewPlayer.stop();
      await _previewPlayer.setReleaseMode(ReleaseMode.stop);
      await _previewPlayer.play(_sourceFor(source));
    } catch (_) {
      // 試聴できない環境でも設定変更自体はブロックしない。
    }
  }

  Source _sourceFor(String source) =>
      source.startsWith('http') ? UrlSource(source) : AssetSource(source);

  Future<void> dispose() async {
    await _ringtoneTimesSub?.cancel();
    await _ringtonePlayer.dispose();
    await _callingPlayer.dispose();
    await _joinPlayer.dispose();
    await _leavePlayer.dispose();
    await _previewPlayer.dispose();
  }
}
