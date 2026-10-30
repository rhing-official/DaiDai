import 'package:daidai/widgets/pdf_preview_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('高さはページの縦横比で決まり、縦に長すぎれば上限で止まる', () {
    // A4（縦長）: 280幅なら約396 → 上限360で止まる。
    expect(
      pdfPreviewHeight(pageWidth: 595, pageHeight: 842, width: 280),
      kPdfPreviewMaxHeight,
    );
    // 横長スライド（16:9）は縦横比どおり。
    expect(
      pdfPreviewHeight(pageWidth: 1600, pageHeight: 900, width: 280),
      closeTo(157.5, 0.01),
    );
    expect(
      pdfPreviewHeight(pageWidth: 0, pageHeight: 100, width: 280),
      kPdfPreviewMaxHeight,
    );
  });

  test('プレビュー対象の上限はビューアで開ける上限より小さい', () {
    expect(kMaxPdfThumbnailBytes, lessThan(50 * 1024 * 1024));
  });
}
