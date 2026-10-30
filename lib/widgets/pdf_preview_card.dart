import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../l10n/strings.dart';
import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import 'glass/glass_surface.dart';
import 'media_preview_frame.dart';
import 'pdf_viewer_screen.dart';

/// メッセージ上にプレビューを出すPDFの上限サイズ（取得が増えるため、アプリ内で
/// 開ける上限[kMaxPdfPreviewBytes]より小さくする）。
const kMaxPdfThumbnailBytes = 20 * 1024 * 1024;

/// プレビューカードの幅と最大高さ（添付画像の幅280に合わせる）。
const kPdfPreviewWidth = 280.0;
const kPdfPreviewMaxHeight = 360.0;

/// ページの縦横比[pageWidth]×[pageHeight]から、幅[width]で描いた時の高さ。
/// 縦に長すぎる場合は[kPdfPreviewMaxHeight]で止める（上端から切り抜く）。
double pdfPreviewHeight({
  required double pageWidth,
  required double pageHeight,
  required double width,
}) {
  if (pageWidth <= 0) return kPdfPreviewMaxHeight;
  final height = width * pageHeight / pageWidth;
  return height > kPdfPreviewMaxHeight ? kPdfPreviewMaxHeight : height;
}

/// メッセージ上のPDFのプレビュー（2026-10-30追加）。ファイル名の下に1ページ目を、
/// 添付画像と同じ枠（フラット=アクセント色の細い枠、ガラス=ガラス面、劇画=白黒枠）で
/// 出す。タップで[openPdfViewer]（1ページずつ・スワイプで送るビューア）を開く。
/// 読み込み中は同じ大きさの枠、開けない時は何も出さない（呼び出し側のファイル名の
/// 行だけが残る）。
class PdfPreviewCard extends ConsumerStatefulWidget {
  const PdfPreviewCard({
    required this.url,
    required this.fileName,
    required this.isMe,
    super.key,
  });

  final String url;
  final String fileName;
  final bool isMe;

  @override
  ConsumerState<PdfPreviewCard> createState() => _PdfPreviewCardState();
}

class _PdfPreviewCardState extends ConsumerState<PdfPreviewCard> {
  // 文書の参照は1度だけ作る。ビルドのたびに作り直すと（ポインターを乗せた時の
  // 再ビルド等で）別の参照とみなされて読み込み直され、枠内が白くなっていた
  // （2026-10-30修正）。
  late final PdfDocumentRef _documentRef = PdfDocumentRefUri(
    Uri.parse(widget.url),
  );

  String get url => widget.url;
  String get fileName => widget.fileName;
  bool get isMe => widget.isMe;

  @override
  Widget build(BuildContext context) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final strings = ref.watch(appStringsProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? (constraints.maxWidth < kPdfPreviewWidth
                  ? constraints.maxWidth
                  : kPdfPreviewWidth)
            : kPdfPreviewWidth;
        return PdfDocumentViewBuilder(
          documentRef: _documentRef,
          loadingBuilder: (context) => _frame(
            context,
            uiStyle,
            isGekiga,
            SizedBox(
              width: width,
              height: width * 1.1,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
          builder: (context, document) {
            if (document == null || document.pages.isEmpty) {
              return const SizedBox.shrink();
            }
            final page = document.pages.first;
            final shown = pdfPreviewHeight(
              pageWidth: page.width,
              pageHeight: page.height,
              width: width,
            );
            final full = width * page.height / page.width;
            final count = document.pages.length;
            return _frame(
              context,
              uiStyle,
              isGekiga,
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    openPdfViewer(context, url: url, fileName: fileName),
                child: SizedBox(
                  width: width,
                  height: shown,
                  child: Stack(
                    children: [
                      // 縦に長いページは、上端から[shown]の高さだけ見せる。
                      ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: 0,
                          maxHeight: full,
                          child: SizedBox(
                            width: width,
                            height: full,
                            child: PdfPageView(
                              document: document,
                              pageNumber: 1,
                              // 既定のドロップシャドウは使わない（影は不使用の方針）。
                              decoration: const BoxDecoration(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (count > 1)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              strings.pdfPageCount(count),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 添付画像と同じ枠（`chat_screen.dart`の`_borderedMediaFrame`と同じ規則）。
  Widget _frame(
    BuildContext context,
    AppUiStyle uiStyle,
    bool isGekiga,
    Widget child,
  ) {
    final framed = mediaPreviewFrame(
      isGekiga: isGekiga,
      isMe: isMe,
      child: child,
    );
    if (isGekiga) return framed;
    final radius = BorderRadius.circular(mediaPreviewContentRadius);
    if (uiStyle == AppUiStyle.glass) {
      return GlassSurface(borderRadius: radius, child: framed);
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.primary),
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: framed,
    );
  }
}
