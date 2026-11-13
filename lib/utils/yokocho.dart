import 'kiwami.dart';

/// daidai横丁（ぺったんのWebストア、HomePage-Rhingリポジトリ）のトップ。
const kYokochoUrl = 'https://rhing.jp/daidai-yokocho';

/// アプリ内からdaidai横丁へのリンクを出してよいか（2026-11-13）。
///
/// iOS App Store・Google Playのストア版は、外部サイトへの購入誘導にストアの
/// プログラム登録・課金（IAP/Play課金）の併設が要るため、登録するまでは出さない。
/// Web・デスクトップ・APKの直接配布（[PurchaseChannel.standard]）では出す。
/// 詳細は`文書/手数料対策.md`。
bool yokochoLinksAllowed() =>
    currentPurchaseChannel() == PurchaseChannel.standard;

/// 横丁のURL。[packId]があればそのパックのページ、無ければトップ。
/// [platform]は横丁側が手数料込みの価格表示を出し分けるための値。
Uri yokochoUri({String? packId, String? platform}) {
  final base = packId == null ? kYokochoUrl : '$kYokochoUrl/$packId';
  final uri = Uri.parse(base);
  return platform == null
      ? uri
      : uri.replace(queryParameters: {'platform': platform});
}
