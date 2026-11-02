import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// チャットの音声添付（プレビュー再生）の再生状態（2026-11-02）。
///
/// 以前は各メッセージのプレビュー行が自分の`AudioPlayer`を持っていたため、メッセージが
/// スクロールで画面から外れて破棄される（約9件離れる）と再生も止まっていた。再生は
/// アプリ全体で1つのプレイヤーが持ち、止めるまで続ける。プレビュー行とバナーは、この
/// 状態を見て表示・操作するだけ。
class AudioPlaybackState {
  const AudioPlaybackState({
    this.messageId,
    this.title = '',
    this.playing = false,
    this.position = Duration.zero,
    this.duration,
  });

  /// 再生中（または一時停止中）のメッセージid。何も再生していなければnull。
  final String? messageId;

  /// バナーに出すファイル名。
  final String title;
  final bool playing;
  final Duration position;
  final Duration? duration;

  bool get active => messageId != null;

  static const idle = AudioPlaybackState();

  AudioPlaybackState copyWith({
    bool? playing,
    Duration? position,
    Duration? duration,
  }) => AudioPlaybackState(
    messageId: messageId,
    title: title,
    playing: playing ?? this.playing,
    position: position ?? this.position,
    duration: duration ?? this.duration,
  );
}

class AudioPlaybackNotifier extends Notifier<AudioPlaybackState> {
  AudioPlayer? _player;
  final List<StreamSubscription<Object?>> _subs = [];

  @override
  AudioPlaybackState build() {
    ref.onDispose(() {
      for (final sub in _subs) {
        sub.cancel();
      }
      _player?.dispose();
    });
    return AudioPlaybackState.idle;
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _player = player;
    _subs
      ..add(
        player.onPlayerStateChanged.listen((s) {
          if (!state.active) return;
          if (s == PlayerState.completed || s == PlayerState.stopped) {
            // 最後まで再生した、または止めた。バナーを消す。
            state = AudioPlaybackState.idle;
          } else {
            state = state.copyWith(playing: s == PlayerState.playing);
          }
        }),
      )
      ..add(
        player.onPositionChanged.listen((p) {
          if (state.active) state = state.copyWith(position: p);
        }),
      )
      ..add(
        player.onDurationChanged.listen((d) {
          if (state.active) state = state.copyWith(duration: d);
        }),
      );
    return player;
  }

  /// [messageId]の音声の再生・一時停止を切り替える。別の音声を再生中なら、そちらを止めて
  /// この音声を最初から再生する。
  Future<void> toggle({
    required String messageId,
    required String url,
    required String title,
  }) async {
    try {
      final player = _ensurePlayer();
      if (state.messageId == messageId) {
        if (state.playing) {
          await player.pause();
        } else {
          await player.resume();
        }
        return;
      }
      state = AudioPlaybackState(messageId: messageId, title: title);
      await player.stop();
      // `stop`が出す停止の通知で上の状態が消えないよう、再生を始める前に状態を作り直す。
      state = AudioPlaybackState(messageId: messageId, title: title);
      await player.play(UrlSource(url));
    } catch (_) {
      // 再生できない環境でもファイル自体のダウンロードは引き続き行える。
      state = AudioPlaybackState.idle;
    }
  }

  Future<void> pause() async {
    try {
      await _player?.pause();
    } catch (_) {}
  }

  Future<void> resume() async {
    try {
      await _player?.resume();
    } catch (_) {}
  }

  /// 再生を止める（バナーの停止ボタン）。位置も捨てて、バナーを消す。
  Future<void> stop() async {
    state = AudioPlaybackState.idle;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  Future<void> seek(Duration position) async {
    try {
      await _player?.seek(position);
    } catch (_) {
      // シークに失敗しても致命的ではないため無視する。
    }
  }
}

final audioPlaybackProvider =
    NotifierProvider<AudioPlaybackNotifier, AudioPlaybackState>(
      AudioPlaybackNotifier.new,
    );
