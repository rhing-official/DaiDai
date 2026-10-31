import 'dart:typed_data';

/// ISO BMFF（mp4・m4a・mov・3gp等）が音声トラックだけでできているかを、
/// ファイルの中身から判定する（2026-10-31追加）。CDの取り込み等で、音声だけの
/// ファイルが`.mp4`で作られることがあるため、拡張子では区別できない。
///
/// `ftyp`で始まり、`moov`内の全`trak`のハンドラ種別（`hdlr`）に`soun`があって
/// `vide`が1つも無ければ真。`moov`が見つからない・壊れている場合は、例外を
/// 投げずに偽（従来どおり動画・ファイルとして扱う）。
bool isAudioOnlyIsoBmff(Uint8List bytes) {
  if (bytes.length < 12 || _type(bytes, 4) != 'ftyp') return false;
  final moov = _findBox(bytes, 0, bytes.length, 'moov');
  if (moov == null) return false;
  var hasSound = false;
  var offset = moov.start;
  while (true) {
    final trak = _findBox(bytes, offset, moov.end, 'trak');
    if (trak == null) break;
    offset = trak.end;
    final mdia = _findBox(bytes, trak.start, trak.end, 'mdia');
    final hdlr = mdia == null
        ? null
        : _findBox(bytes, mdia.start, mdia.end, 'hdlr');
    // hdlrの中身: version/flags(4) + pre_defined(4) + handler_type(4)
    if (hdlr == null || hdlr.end - hdlr.start < 12) return false;
    final handler = _type(bytes, hdlr.start + 8);
    if (handler == 'vide') return false;
    if (handler == 'soun') hasSound = true;
  }
  return hasSound;
}

class _Box {
  const _Box(this.start, this.end);

  /// 中身の開始位置（ヘッダーの直後）と終了位置。
  final int start;
  final int end;
}

String _type(Uint8List bytes, int offset) {
  if (offset + 4 > bytes.length) return '';
  return String.fromCharCodes(bytes.sublist(offset, offset + 4));
}

/// [from]〜[to]の範囲に並ぶボックスから、最初の[type]を探す。
_Box? _findBox(Uint8List bytes, int from, int to, String type) {
  final data = ByteData.sublistView(bytes);
  var offset = from;
  final limit = to < bytes.length ? to : bytes.length;
  while (offset + 8 <= limit) {
    var size = data.getUint32(offset);
    var header = 8;
    if (size == 1) {
      if (offset + 16 > limit) return null;
      final big = data.getUint64(offset + 8);
      if (big > limit) return null;
      size = big;
      header = 16;
    } else if (size == 0) {
      size = limit - offset;
    }
    if (size < header || offset + size > limit) return null;
    if (_type(bytes, offset + 4) == type) {
      return _Box(offset + header, offset + size);
    }
    offset += size;
  }
  return null;
}
