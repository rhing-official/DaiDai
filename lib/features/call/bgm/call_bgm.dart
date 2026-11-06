import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'bgm_mixer.dart';
import 'bgm_track.dart';

/// 通話中のBGMの再生状態と操作（2026-11-03）。通話コントローラー（一対・広場）が1つずつ持つ。
/// 再生中だけ、マイクと曲を混ぜたトラックを送信に使い、止めると元のマイクのトラックへ戻す。
/// 曲は端末内（[BgmStorage]）にあり、サーバーには上げない。
class CallBgm extends ChangeNotifier {
  CallBgm({
    required this.storage,
    required this.micTrack,
    required this.replaceOutgoingAudio,
    required this.onPlayingChanged,
    BgmMixer? mixer,
  }) : _mixer = mixer ?? BgmMixer();

  final BgmStorage storage;

  /// 元のマイクのトラック（無ければnull）。
  final MediaStreamTrack? Function() micTrack;

  /// 送信中の音声トラックを、全ての相手に対して差し替える。
  final Future<void> Function(MediaStreamTrack track) replaceOutgoingAudio;

  /// 自分の再生が始まった（曲名）／止まった（null）時に、相手へ知らせる。
  final void Function(String? title) onPlayingChanged;

  final BgmMixer _mixer;

  static bool get isSupported => BgmMixer.isSupported;

  List<BgmTrack> _tracks = const [];
  List<BgmTrack> get tracks => _tracks;

  BgmTrack? _current;

  /// 今流している曲（流していなければnull）。
  BgmTrack? get current => _current;
  bool get playing => _current != null;

  double _volume = 0.5;
  double get volume => _volume;

  MediaStreamTrack? _mixed;

  /// 混合中の送信トラック（流していなければnull）。通話の途中で相手が増えた時、
  /// その相手へはマイクの代わりにこれを送る。
  MediaStreamTrack? get mixedTrack => _mixed;

  bool _disposed = false;

  Future<void> loadTracks() async {
    _tracks = await storage.list();
    if (!_disposed) notifyListeners();
  }

  Future<void> addTrack({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    await storage.add(name: name, mimeType: mimeType, bytes: bytes);
    await loadTracks();
  }

  Future<void> removeTrack(BgmTrack track) async {
    if (_current?.id == track.id) await stop();
    await storage.remove(track.id);
    await loadTracks();
  }

  /// [track]を流し始める（流していれば入れ替える）。ユーザー操作の中で呼ぶこと
  /// （ブラウザが自動再生を制限する為）。
  Future<void> play(BgmTrack track) async {
    final mic = micTrack();
    if (mic == null) return;
    final bytes = await storage.bytes(track.id);
    if (bytes == null || _disposed) return;
    if (_mixed == null) {
      final mixed = _mixer.attach(mic);
      _mixed = mixed;
      await replaceOutgoingAudio(mixed);
    }
    _mixer.volume = _volume;
    _current = track;
    notifyListeners();
    onPlayingChanged(track.name);
    try {
      await _mixer.play(bytes, track.mimeType, onEnded: _playNext);
    } catch (_) {
      // 再生出来ない曲（壊れたファイル等）。止めて元に戻す。
      await stop();
    }
  }

  /// 曲が終わったら一覧の次の曲へ（最後の次は先頭。1曲ならその曲を繰り返す）。
  void _playNext() {
    final current = _current;
    if (current == null || _tracks.isEmpty) return;
    final index = _tracks.indexWhere((t) => t.id == current.id);
    final next = _tracks[(index + 1) % _tracks.length];
    play(next);
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _mixer.volume = _volume;
    notifyListeners();
  }

  /// 流すのを止め、送信を元のマイクのトラックへ戻す。
  Future<void> stop() async {
    if (_current == null && _mixed == null) return;
    _mixer.stop();
    final hadMixed = _mixed != null;
    _mixed = null;
    _current = null;
    if (!_disposed) notifyListeners();
    final mic = micTrack();
    if (hadMixed && mic != null) {
      try {
        await replaceOutgoingAudio(mic);
      } catch (_) {
        // 通話が既に切れている等。
      }
    }
    onPlayingChanged(null);
  }

  @override
  void dispose() {
    _disposed = true;
    _mixer.dispose();
    super.dispose();
  }
}
