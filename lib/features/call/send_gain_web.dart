import 'dart:async';
import 'dart:js_interop';

import 'package:dart_webrtc/dart_webrtc.dart';
import 'package:web/web.dart' as web;

import 'call_log.dart';

/// [source]の音声トラックを`GainNode`に通した、処理後のトラック。送る音の音量を、0〜1で変える。
/// 元のトラックは止めない（呼び出し側が持ち続ける。ミュートは処理後のトラックの`enabled`で行う）。
class SendGain {
  SendGain._(this._context, this._gain, this.track);

  final web.AudioContext _context;
  final web.GainNode _gain;

  /// 処理後のトラック（送信の枠へ差し替える）。
  final MediaStreamTrack track;

  static bool get isSupported => true;

  /// 取り込めなければnull（元のトラックのまま送る）。
  static Future<SendGain?> attach(MediaStreamTrack source) async {
    if (source is! MediaStreamTrackWeb) return null;
    web.AudioContext? context;
    try {
      context = web.AudioContext();
      final gain = context.createGain();
      final destination = context.createMediaStreamDestination();
      context
          .createMediaStreamSource(web.MediaStream([source.jsTrack].toJS))
          .connect(gain);
      gain.connect(destination);
      // 自動再生の制限で止まったままだと無音になる為、動いていなければ諦める。
      await context.resume().toDart.timeout(const Duration(seconds: 1));
      if (context.state != 'running') {
        throw StateError('audio context suspended');
      }
      final processed = destination.stream.getAudioTracks().toDart.first;
      return SendGain._(context, gain, MediaStreamTrackWeb(processed));
    } catch (e) {
      callLog('send gain unavailable: $e');
      try {
        context?.close();
      } catch (_) {}
      return null;
    }
  }

  void setGain(double gain) {
    _gain.gain.value = gain.clamp(0.0, 1.0);
  }

  Future<void> dispose() async {
    try {
      await _context.close().toDart;
    } catch (_) {}
  }
}
