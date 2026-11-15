import 'dart:convert';
import 'dart:typed_data';

/// 通話の相手へ知らせる、今流している曲の表示用の情報（曲名・一時停止か・小さなジャケット）。
/// 相手の画面の細いプレーヤーに使う（表示のみ。曲そのものは送らない）。
class BgmNowPlaying {
  const BgmNowPlaying({required this.title, this.paused = false, this.thumb});

  final String title;
  final bool paused;

  /// 縮小したジャケット画像（JPEG。無ければnull）。
  final Uint8List? thumb;

  BgmNowPlaying copyWith({bool? paused}) =>
      BgmNowPlaying(title: title, paused: paused ?? this.paused, thumb: thumb);

  String encode() => jsonEncode({
    't': title,
    if (paused) 'p': true,
    if (thumb != null) 'c': base64Encode(thumb!),
  });

  /// [encode]の逆。読めなければnull。
  static BgmNowPlaying? decode(String text) {
    try {
      final map = jsonDecode(text);
      if (map is! Map) return null;
      final title = map['t'];
      if (title is! String) return null;
      final cover = map['c'];
      return BgmNowPlaying(
        title: title,
        paused: map['p'] == true,
        thumb: cover is String ? base64Decode(cover) : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// 広場の参加者ドキュメント用に、ジャケットをbase64文字列で出し入れする。
  String? get thumbBase64 => thumb == null ? null : base64Encode(thumb!);

  static Uint8List? thumbFromBase64(String? s) {
    if (s == null) return null;
    try {
      return base64Decode(s);
    } catch (_) {
      return null;
    }
  }
}
