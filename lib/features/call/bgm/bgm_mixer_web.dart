import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dart_webrtc/dart_webrtc.dart';
import 'package:web/web.dart' as web;

/// マイク（元のトラック）と曲を`AudioContext`で混ぜ、出力を1本のトラックにする。
/// マイクのミュートは元のトラックの`enabled`で行う（入力が無音になるだけでBGMは続く）。
class BgmMixer {
  static bool get isSupported => true;

  web.AudioContext? _context;
  web.MediaStreamAudioDestinationNode? _destination;
  web.GainNode? _bgmGain;
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
      final bgmGain = context.createGain()
        ..gain.value = _volume
        ..connect(destination);
      final audio = web.HTMLAudioElement();
      context.createMediaElementSource(audio).connect(bgmGain);
      _bgmGain = bgmGain;
      _audio = audio;
    }
    final out = destination.stream.getAudioTracks().toDart.first;
    return MediaStreamTrackWeb(out);
  }

  /// 曲を最初から再生する。終わったら[onEnded]。
  Future<void> play(
    Uint8List bytes,
    String mimeType, {
    void Function()? onEnded,
  }) async {
    final audio = _audio;
    if (audio == null) return;
    stop();
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
    await audio.play().toDart;
  }

  /// 再生を止めて曲を手放す（混合の経路は残す）。
  void stop() {
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

  set volume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _bgmGain?.gain.value = _volume;
  }

  void dispose() {
    stop();
    unawaited(_context?.close().toDart);
    _context = null;
    _destination = null;
    _bgmGain = null;
    _audio = null;
  }
}
