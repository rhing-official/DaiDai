import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dart_webrtc/dart_webrtc.dart';
import 'package:web/web.dart' as web;

/// 再生・一時停止・再開・停止の音の立ち上がり／消え入りの長さ（2026-11-16）。ぷつっと
/// 始まる・切れるのを避けつつ、待たされないよう一瞬にする。
const kBgmFadeIn = Duration(milliseconds: 200);
const kBgmFadeOut = Duration(milliseconds: 200);

/// 曲を切り替える時の、前の曲の消え入り。
const kBgmSwitchFadeOut = Duration(milliseconds: 120);

/// マイク（元のトラック）と曲を`AudioContext`で混ぜ、出力を1本のトラックにする。
/// マイクのミュートは元のトラックの`enabled`で行う（入力が無音になるだけでBGMは続く）。
class BgmMixer {
  static bool get isSupported => true;

  web.AudioContext? _context;
  web.MediaStreamAudioDestinationNode? _destination;
  web.GainNode? _bgmGain;

  /// フェード専用のゲイン（音量用の[_bgmGain]と直列。音量の操作とぶつからない）。
  web.GainNode? _fadeGain;

  /// 再生・停止・一時停止のたびに増やす世代。フェードを待っている間に別の操作が来たら、
  /// 古い方の後処理は行わない。
  int _gen = 0;
  web.HTMLAudioElement? _audio;
  String? _objectUrl;
  double _volume = 0.5;
  JSFunction? _endedListener;

  /// 元のマイクトラックを入力に、混合した出力トラックを返す。ユーザー操作の中で呼ぶ
  /// （ブラウザの自動再生の制限で、`AudioContext`の開始に操作が要る為）。
  MediaStreamTrack attach(MediaStreamTrack mic) {
    final context = _context ??= web.AudioContext();
    unawaited(context.resume().toDart);
    final destination = _destination ??= context.createMediaStreamDestination();
    final micJs = (mic as MediaStreamTrackWeb).jsTrack;
    final micStream = web.MediaStream([micJs].toJS);
    context.createMediaStreamSource(micStream).connect(destination);
    if (_audio == null) {
      // 送信用（相手へ）に加え、自分のスピーカー（`context.destination`）にも出す。以前は送信用に
      // だけ繋いでいた為、相手には聞こえるが自分には全く聞こえなかった（2026-11-15）。
      // マイクの方は自分へ戻さない（自分の声が返ってくる為）。
      final bgmGain = context.createGain()
        ..gain.value = _volume
        ..connect(destination)
        ..connect(context.destination);
      final fadeGain = context.createGain()..connect(bgmGain);
      final audio = web.HTMLAudioElement();
      context.createMediaElementSource(audio).connect(fadeGain);
      _bgmGain = bgmGain;
      _fadeGain = fadeGain;
      _audio = audio;
    }
    final out = destination.stream.getAudioTracks().toDart.first;
    return MediaStreamTrackWeb(out);
  }

  /// フェード用のゲインを、今の値から[target]へ[duration]かけて直線で動かす。動きが終わる頃に
  /// 完了する。
  Future<void> _fadeTo(double target, Duration duration) {
    final param = _fadeGain?.gain;
    final context = _context;
    if (param == null || context == null) return Future.value();
    final now = context.currentTime;
    param
      ..cancelScheduledValues(now)
      ..setValueAtTime(param.value, now)
      ..linearRampToValueAtTime(target, now + duration.inMilliseconds / 1000);
    return Future<void>.delayed(duration);
  }

  /// 実際に音が出ているか（曲が読み込まれ、止まっても終わってもいない）。
  bool get _audible {
    final audio = _audio;
    return audio != null &&
        !audio.paused &&
        !audio.ended &&
        audio.src.isNotEmpty;
  }

  /// 曲を最初から再生する。終わったら[onEnded]。前の曲が鳴っていれば、一瞬で消え入ってから
  /// 切り替え、新しい曲は消えた状態から立ち上がる。
  Future<void> play(
    Uint8List bytes,
    String mimeType, {
    void Function()? onEnded,
  }) async {
    final audio = _audio;
    if (audio == null) return;
    final gen = ++_gen;
    if (_audible) {
      await _fadeTo(0, kBgmSwitchFadeOut);
      if (gen != _gen) return;
    }
    _release();
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    _objectUrl = web.URL.createObjectURL(blob);
    audio.src = _objectUrl!;
    if (onEnded != null) {
      _endedListener = ((web.Event _) => onEnded()).toJS;
      audio.addEventListener('ended', _endedListener);
    }
    _fadeGain?.gain
      ?..cancelScheduledValues(_context?.currentTime ?? 0)
      ..value = 0;
    await audio.play().toDart;
    if (gen != _gen) return;
    unawaited(_fadeTo(1, kBgmFadeIn));
  }

  /// 再生を止めて曲を手放す（混合の経路は残す）。[fade]なら、一瞬で消え入ってから止める
  /// （消え入りが終わると完了する）。通話の終了などは[fade]なしで即時。
  Future<void> stop({bool fade = true}) async {
    final gen = ++_gen;
    if (fade && _audible) {
      await _fadeTo(0, kBgmFadeOut);
      if (gen != _gen) return;
    }
    _release();
  }

  void _release() {
    final audio = _audio;
    if (audio != null) {
      final listener = _endedListener;
      if (listener != null) audio.removeEventListener('ended', listener);
      audio.pause();
      audio.removeAttribute('src');
      audio.load();
    }
    _endedListener = null;
    final url = _objectUrl;
    if (url != null) web.URL.revokeObjectURL(url);
    _objectUrl = null;
  }

  /// 今の再生位置と、曲の長さ（読み込み前・長さ不明はnull）。
  Duration get position {
    final t = _audio?.currentTime ?? 0;
    return Duration(milliseconds: ((t.isFinite ? t : 0) * 1000).round());
  }

  Duration? get duration {
    final d = _audio?.duration;
    if (d == null || !d.isFinite || d <= 0) return null;
    return Duration(milliseconds: (d * 1000).round());
  }

  /// 再生位置を動かす（曲が読み込まれていない間は何もしない）。
  void seek(Duration to) {
    final audio = _audio;
    if (audio == null || duration == null) return;
    audio.currentTime = to.inMilliseconds / 1000;
  }

  bool get paused => _audio?.paused ?? true;

  /// 一時停止。一瞬で消え入ってから止める。混合の経路・曲は残す（[resume]で続きから）。
  Future<void> pause() async {
    final gen = ++_gen;
    await _fadeTo(0, kBgmFadeOut);
    if (gen != _gen) return;
    _audio?.pause();
  }

  /// 続きから再開する。消えた状態から一瞬で立ち上がる。
  Future<void> resume() async {
    final audio = _audio;
    if (audio == null) return;
    final gen = ++_gen;
    await audio.play().toDart;
    if (gen != _gen) return;
    unawaited(_fadeTo(1, kBgmFadeIn));
  }

  set volume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _bgmGain?.gain.value = _volume;
  }

  void dispose() {
    unawaited(stop(fade: false));
    unawaited(_context?.close().toDart);
    _context = null;
    _destination = null;
    _bgmGain = null;
    _fadeGain = null;
    _audio = null;
  }
}
