import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:dart_webrtc/dart_webrtc.dart';
import 'package:web/web.dart' as web;

import 'call_log.dart';

/// マイクの生のトラックを、RNNoise（`web/rnnoise/`のWASMと`AudioWorklet`）に通して、
/// 処理後のトラックに置き換える（2026-11-15）。置き換えるのは[MediaStream]の中の音声トラック
/// なので、送信・ミュート（`enabled`）・BGMの混合・発話判定は変更しなくてよい。
/// 取り込みに失敗したら何もせずnullを返し、生のトラックのまま通話を続ける。
class MicDenoiser {
  MicDenoiser._(this._context, this._raw);

  final web.AudioContext _context;
  final MediaStreamTrack _raw;

  static bool get isSupported => true;

  static const _processorName = '@sapphi-red/web-noise-suppressor/rnnoise';

  /// [stream]の音声トラックを、処理後のトラックに置き換える。置き換えられなければnull。
  static Future<MicDenoiser?> attach(MediaStream stream) async {
    final raw = stream.getAudioTracks().firstOrNull;
    if (raw is! MediaStreamTrackWeb) return null;
    web.AudioContext? context;
    try {
      // RNNoiseは48kHz前提。
      context = web.AudioContext(web.AudioContextOptions(sampleRate: 48000));
      await context.audioWorklet
          .addModule('rnnoise/workletProcessor.js')
          .toDart;
      final wasm = await _fetchWasm();
      final options = JSObject()
        ..setProperty('maxChannels'.toJS, 1.toJS)
        ..setProperty('wasmBinary'.toJS, wasm);
      final node = web.AudioWorkletNode(
        context,
        _processorName,
        web.AudioWorkletNodeOptions(
          numberOfInputs: 1,
          numberOfOutputs: 1,
          outputChannelCount: [1.toJS].toJS,
          processorOptions: options,
        ),
      );
      final destination = context.createMediaStreamDestination();
      context
          .createMediaStreamSource(web.MediaStream([raw.jsTrack].toJS))
          .connect(node);
      node.connect(destination);
      // 自動再生の制限で止まったままだと無音になる為、動いていなければ諦める。
      await context.resume().toDart.timeout(const Duration(seconds: 1));
      if (context.state != 'running')
        throw StateError('audio context suspended');
      final processed = destination.stream.getAudioTracks().toDart.first;
      await stream.removeTrack(raw);
      await stream.addTrack(MediaStreamTrackWeb(processed));
      callLog('mic denoise (rnnoise) on');
      return MicDenoiser._(context, raw);
    } catch (e) {
      callLog('mic denoise unavailable: $e');
      try {
        context?.close();
      } catch (_) {}
      return null;
    }
  }

  /// SIMD対応ならSIMD版のWASMを取る。
  static Future<JSAny> _fetchWasm() async {
    final simd = _supportsSimd();
    final response = await web.window
        .fetch(
          (simd ? 'rnnoise/rnnoise_simd.wasm' : 'rnnoise/rnnoise.wasm').toJS,
        )
        .toDart;
    if (!response.ok) throw StateError('wasm fetch ${response.status}');
    return await response.arrayBuffer().toDart;
  }

  static bool _supportsSimd() {
    try {
      final wasm = web.window.getProperty<JSObject>('WebAssembly'.toJS);
      final bytes = Uint8List.fromList([
        0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 96, 0, 1, 123, 3, 2, 1, 0, //
        10, 10, 1, 8, 0, 65, 0, 253, 15, 253, 98, 11,
      ]);
      return wasm.callMethod<JSBoolean>('validate'.toJS, bytes.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  /// 処理を止めて、元のマイクのトラックも手放す（通話の終了時）。
  Future<void> dispose() async {
    try {
      await _raw.stop();
    } catch (_) {}
    try {
      await _context.close().toDart;
    } catch (_) {}
  }
}
