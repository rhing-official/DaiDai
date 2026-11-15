import 'dart:convert';
import 'dart:typed_data';

/// 曲に埋め込まれたジャケット画像（2026-11-15）。
class BgmCover {
  const BgmCover(this.data, this.mimeType);

  final Uint8List data;
  final String mimeType;
}

/// mp3（ID3v2のAPIC）・FLAC（PICTUREブロック）・m4a/mp4（`covr`）に埋め込まれた
/// ジャケット画像を取り出す。無い・読めない場合はnull（例外は投げない）。
BgmCover? extractBgmCover(Uint8List bytes) {
  try {
    if (bytes.length > 10 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      return _fromId3(bytes);
    }
    if (bytes.length > 4 &&
        bytes[0] == 0x66 &&
        bytes[1] == 0x4C &&
        bytes[2] == 0x61 &&
        bytes[3] == 0x43) {
      return _fromFlac(bytes);
    }
    if (bytes.length > 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return _fromMp4(bytes);
    }
  } catch (_) {
    // 壊れたタグ。ジャケットなしとして扱う。
  }
  return null;
}

int _be32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

int _syncsafe(Uint8List b, int o) =>
    (b[o] << 21) | (b[o + 1] << 14) | (b[o + 2] << 7) | b[o + 3];

String _ascii(Uint8List b, int start, int end) =>
    String.fromCharCodes(b.sublist(start, end));

String _imageMime(Uint8List d, [String? declared]) {
  if (d.length > 3 && d[0] == 0xFF && d[1] == 0xD8) return 'image/jpeg';
  if (d.length > 4 && d[0] == 0x89 && d[1] == 0x50) return 'image/png';
  if (declared != null && declared.startsWith('image/')) return declared;
  return 'image/jpeg';
}

BgmCover? _fromId3(Uint8List b) {
  final version = b[3];
  if (version < 3 || version > 4) return null; // ID3v2.3/2.4のみ
  final flags = b[5];
  final tagSize = _syncsafe(b, 6);
  var pos = 10;
  if (flags & 0x40 != 0 && pos + 4 <= b.length) {
    // 拡張ヘッダーを飛ばす。
    final ext = version == 4 ? _syncsafe(b, pos) : _be32(b, pos) + 4;
    pos += ext;
  }
  final end = (10 + tagSize).clamp(0, b.length);
  while (pos + 10 <= end) {
    final id = _ascii(b, pos, pos + 4);
    if (id.codeUnitAt(0) == 0) break;
    final size = version == 4 ? _syncsafe(b, pos + 4) : _be32(b, pos + 4);
    final body = pos + 10;
    if (size <= 0 || body + size > b.length) break;
    if (id == 'APIC') {
      final encoding = b[body];
      var p = body + 1;
      final mimeStart = p;
      while (p < body + size && b[p] != 0) {
        p++;
      }
      final mime = _ascii(b, mimeStart, p);
      p++; // 終端
      p++; // 画像の種類
      // 説明文（文字コードで終端が1バイトか2バイトか違う）。
      if (encoding == 0 || encoding == 3) {
        while (p < body + size && b[p] != 0) {
          p++;
        }
        p++;
      } else {
        while (p + 1 < body + size && !(b[p] == 0 && b[p + 1] == 0)) {
          p += 2;
        }
        p += 2;
      }
      if (p >= body + size) return null;
      final data = Uint8List.fromList(b.sublist(p, body + size));
      return BgmCover(data, _imageMime(data, mime));
    }
    pos = body + size;
  }
  return null;
}

BgmCover? _fromFlac(Uint8List b) {
  var pos = 4;
  while (pos + 4 <= b.length) {
    final header = b[pos];
    final isLast = header & 0x80 != 0;
    final type = header & 0x7F;
    final len = (b[pos + 1] << 16) | (b[pos + 2] << 8) | b[pos + 3];
    final body = pos + 4;
    if (body + len > b.length) return null;
    if (type == 6) {
      var p = body + 4; // 種類
      final mimeLen = _be32(b, p);
      p += 4;
      final mime = _ascii(b, p, p + mimeLen);
      p += mimeLen;
      final descLen = _be32(b, p);
      p += 4 + descLen;
      p += 16; // 幅・高さ・色深度・色数
      final dataLen = _be32(b, p);
      p += 4;
      if (p + dataLen > b.length) return null;
      final data = Uint8List.fromList(b.sublist(p, p + dataLen));
      return BgmCover(data, _imageMime(data, mime));
    }
    if (isLast) break;
    pos = body + len;
  }
  return null;
}

/// MP4の入れ子の箱（moov→udta→meta→ilst→covr→data）をたどる。
BgmCover? _fromMp4(Uint8List b) {
  Uint8List? find(int start, int end, List<String> path) {
    var pos = start;
    while (pos + 8 <= end) {
      var size = _be32(b, pos);
      final type = _ascii(b, pos + 4, pos + 8);
      var header = 8;
      if (size == 1 && pos + 16 <= end) {
        size = _be32(b, pos + 12); // 64bitの下位だけ使う
        header = 16;
      }
      if (size < header) return null;
      final boxEnd = (pos + size).clamp(0, end);
      if (type == path.first) {
        var inner = pos + header;
        if (type == 'meta') inner += 4; // バージョン・フラグ
        if (path.length == 1) return b.sublist(inner, boxEnd);
        final found = find(inner, boxEnd, path.sublist(1));
        if (found != null) return found;
      }
      pos = boxEnd;
    }
    return null;
  }

  final data = find(0, b.length, ['moov', 'udta', 'meta', 'ilst', 'covr']);
  if (data == null || data.length < 16) return null;
  // 中の`data`の箱: サイズ4 + 'data' 4 + 種類4 + 予約4 + 本体。
  if (_ascii(data, 4, 8) != 'data') return null;
  final image = Uint8List.fromList(data.sublist(16));
  return BgmCover(image, _imageMime(image));
}

/// 曲のタグ（2026-11-15）。無い項目はnull。
class BgmMeta {
  const BgmMeta({
    this.title,
    this.artist,
    this.album,
    this.trackNo,
    this.discNo,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? trackNo;

  /// ディスク番号（`1/2`の1。無ければnull、2026-11-15追加）。
  final int? discNo;
}

/// mp3（ID3v2）・FLAC（Vorbisコメント）・m4a/mp4（`ilst`）のタグから、曲名・アーティスト・
/// アルバム・トラック番号を取り出す。読めなければ空の[BgmMeta]（例外は投げない）。
BgmMeta extractBgmMeta(Uint8List bytes) {
  try {
    if (bytes.length > 10 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      return _metaFromId3(bytes);
    }
    if (bytes.length > 4 &&
        bytes[0] == 0x66 &&
        bytes[1] == 0x4C &&
        bytes[2] == 0x61 &&
        bytes[3] == 0x43) {
      return _metaFromFlac(bytes);
    }
    if (bytes.length > 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return _metaFromMp4(bytes);
    }
  } catch (_) {}
  return const BgmMeta();
}

String? _clean(String? s) {
  final t = s?.replaceAll('\u0000', '').trim();
  return (t == null || t.isEmpty) ? null : t;
}

int? _trackNo(String? s) {
  final head = _clean(s)?.split('/').first;
  return head == null ? null : int.tryParse(head.trim());
}

/// ID3のテキスト（先頭1バイトが文字コード）を文字列にする。
String _id3Text(Uint8List b, int start, int end) {
  if (end <= start) return '';
  final enc = b[start];
  final body = b.sublist(start + 1, end);
  switch (enc) {
    case 1:
    case 2:
      var data = body;
      var littleEndian = enc == 1;
      if (data.length >= 2) {
        if (data[0] == 0xFF && data[1] == 0xFE) {
          littleEndian = true;
          data = data.sublist(2);
        } else if (data[0] == 0xFE && data[1] == 0xFF) {
          littleEndian = false;
          data = data.sublist(2);
        }
      }
      final units = <int>[];
      for (var i = 0; i + 1 < data.length; i += 2) {
        units.add(
          littleEndian
              ? data[i] | (data[i + 1] << 8)
              : (data[i] << 8) | data[i + 1],
        );
      }
      return String.fromCharCodes(units);
    case 3:
      return utf8Decode(body);
    default:
      return String.fromCharCodes(body); // ISO-8859-1
  }
}

String utf8Decode(List<int> bytes) =>
    const Utf8Decoder(allowMalformed: true).convert(bytes);

BgmMeta _metaFromId3(Uint8List b) {
  final version = b[3];
  if (version < 3 || version > 4) return const BgmMeta();
  final tagSize = _syncsafe(b, 6);
  var pos = 10;
  if (b[5] & 0x40 != 0 && pos + 4 <= b.length) {
    pos += version == 4 ? _syncsafe(b, pos) : _be32(b, pos) + 4;
  }
  final end = (10 + tagSize).clamp(0, b.length);
  String? title, artist, album, track, disc;
  while (pos + 10 <= end) {
    final id = _ascii(b, pos, pos + 4);
    if (id.codeUnitAt(0) == 0) break;
    final size = version == 4 ? _syncsafe(b, pos + 4) : _be32(b, pos + 4);
    final body = pos + 10;
    if (size <= 0 || body + size > b.length) break;
    switch (id) {
      case 'TIT2':
        title = _id3Text(b, body, body + size);
      case 'TPE1':
        artist = _id3Text(b, body, body + size);
      case 'TALB':
        album = _id3Text(b, body, body + size);
      case 'TRCK':
        track = _id3Text(b, body, body + size);
      case 'TPOS':
        disc = _id3Text(b, body, body + size);
    }
    pos = body + size;
  }
  return BgmMeta(
    title: _clean(title),
    artist: _clean(artist),
    album: _clean(album),
    trackNo: _trackNo(track),
    discNo: _trackNo(disc),
  );
}

BgmMeta _metaFromFlac(Uint8List b) {
  var pos = 4;
  while (pos + 4 <= b.length) {
    final header = b[pos];
    final isLast = header & 0x80 != 0;
    final type = header & 0x7F;
    final len = (b[pos + 1] << 16) | (b[pos + 2] << 8) | b[pos + 3];
    final body = pos + 4;
    if (body + len > b.length) break;
    if (type == 4) {
      final data = ByteData.sublistView(b, body, body + len);
      var p = 0;
      final vendor = data.getUint32(p, Endian.little);
      p += 4 + vendor;
      final count = data.getUint32(p, Endian.little);
      p += 4;
      String? title, artist, album, track, disc;
      for (var i = 0; i < count && p + 4 <= len; i++) {
        final n = data.getUint32(p, Endian.little);
        p += 4;
        if (p + n > len) break;
        final text = utf8Decode(b.sublist(body + p, body + p + n));
        p += n;
        final eq = text.indexOf('=');
        if (eq < 0) continue;
        final key = text.substring(0, eq).toUpperCase();
        final value = text.substring(eq + 1);
        switch (key) {
          case 'TITLE':
            title = value;
          case 'ARTIST':
            artist = value;
          case 'ALBUM':
            album = value;
          case 'TRACKNUMBER':
            track = value;
          case 'DISCNUMBER':
            disc = value;
        }
      }
      return BgmMeta(
        title: _clean(title),
        artist: _clean(artist),
        album: _clean(album),
        trackNo: _trackNo(track),
        discNo: _trackNo(disc),
      );
    }
    if (isLast) break;
    pos = body + len;
  }
  return const BgmMeta();
}

BgmMeta _metaFromMp4(Uint8List b) {
  // moov→udta→meta→ilst の中身（子の箱の並び）を取る。
  Uint8List? ilst;
  Uint8List? find(Uint8List data, List<String> path, {bool skipMeta = false}) {
    var pos = 0;
    while (pos + 8 <= data.length) {
      final size = _be32(data, pos);
      final type = _ascii(data, pos + 4, pos + 8);
      if (size < 8) return null;
      final boxEnd = (pos + size).clamp(0, data.length);
      if (type == path.first) {
        var inner = pos + 8;
        if (type == 'meta') inner += 4;
        final content = data.sublist(inner, boxEnd);
        if (path.length == 1) return content;
        final found = find(content, path.sublist(1));
        if (found != null) return found;
      }
      pos = boxEnd;
    }
    return null;
  }

  ilst = find(b, ['moov', 'udta', 'meta', 'ilst']);
  if (ilst == null) return const BgmMeta();
  String? title, artist, album;
  int? track, disc;
  var pos = 0;
  while (pos + 8 <= ilst.length) {
    final size = _be32(ilst, pos);
    if (size < 8) break;
    final key = String.fromCharCodes(ilst.sublist(pos + 4, pos + 8));
    final end = (pos + size).clamp(0, ilst.length);
    // 中の`data`の箱: サイズ4 + 'data' 4 + 種類4 + 予約4 + 本体。
    if (end - pos >= 8 + 16 && _ascii(ilst, pos + 12, pos + 16) == 'data') {
      final value = ilst.sublist(pos + 24, end);
      switch (key) {
        case '©nam':
          title = utf8Decode(value);
        case '©ART':
          artist = utf8Decode(value);
        case '©alb':
          album = utf8Decode(value);
        case 'trkn':
          if (value.length >= 4) track = (value[2] << 8) | value[3];
        case 'disk':
          if (value.length >= 4) disc = (value[2] << 8) | value[3];
      }
    }
    pos = end;
  }
  return BgmMeta(
    title: _clean(title),
    artist: _clean(artist),
    album: _clean(album),
    trackNo: track != null && track > 0 ? track : null,
    discNo: disc != null && disc > 0 ? disc : null,
  );
}
