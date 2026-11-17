import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// ぺったん画像のURLがSVGか（2026-11-17）。Storageのダウンロード用URLは
/// `?alt=media&token=...`が付くため、クエリを除いたパスの拡張子で判定する。
bool isSvgUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.path.toLowerCase().endsWith('.svg');
}

/// ぺったん画像（Storageの画像URL）を表示する。SVGは`Image.network`で表示できないため
/// `SvgPicture.network`に、それ以外は従来の`Image.network`に振り分ける。
/// [cacheWidth]はラスタ画像の縮小読み込み用で、SVGには効かない。
class StickerImage extends StatelessWidget {
  const StickerImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.cacheWidth,
    this.errorBuilder,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    if (isSvgUrl(url)) {
      return SvgPicture.network(
        url,
        width: width,
        height: height,
        fit: fit,
        placeholderBuilder: (_) => SizedBox(width: width, height: height),
        errorBuilder: errorBuilder == null
            ? null
            : (context, error, stackTrace) =>
                  errorBuilder!(context, error, stackTrace),
      );
    }
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      errorBuilder: errorBuilder,
    );
  }
}
