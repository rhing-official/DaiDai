import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../models/message.dart';
import 'blurred_viewer_route.dart';
import 'confirm_download_dialog.dart';
import 'viewer_nav_arrows.dart';
import 'swipe_gestures.dart' show PinchPriorityPageView, ZoomReporter;

/// アプリ内で開くPDFの上限サイズ。超える大きさは取得が重いので従来どおり
/// ダウンロードのみ。
const kMaxPdfPreviewBytes = 50 * 1024 * 1024;

/// この添付をPDFビューアで開けるか。拡張子`pdf`またはMIMEが`application/pdf`で、
/// サイズが上限以下のもの。
bool isPreviewablePdf(MessageFileMetadata metadata) =>
    (metadata.extension.toLowerCase() == 'pdf' ||
        metadata.mimeType == 'application/pdf') &&
    metadata.sizeBytes <= kMaxPdfPreviewBytes;

/// PDFをアプリ内で開く（2026-10-30追加）。写真・動画のビューア
/// （`openMediaViewer`）と同じく、中身を読むための全画面ビューアなので
/// `Navigator.push`の別ルートで開く。ダウンロードは不要で、閉じるとメッセージ
/// 画面にそのまま戻る。
Future<void> openPdfViewer(
  BuildContext context, {
  required String url,
  required String fileName,
}) {
  return Navigator.of(context).push(
    blurredViewerRoute((_) => PdfViewerScreen(url: url, fileName: fileName)),
  );
}

/// PDFの全画面ビューア。画像・動画のビューア（`MediaViewerScreen`）と同じく
/// **1ページずつ**画面に収めて表示し、左へスワイプで次のページ・右で前のページ
/// （`PinchPriorityPageView`）。ピンチ（PCは`Ctrl`+ホイール）でズーム・パン、
/// 下スワイプ・`Esc`・戻るで閉じる。PCは`←`/`→`・`PageUp`/`PageDown`でページ送り。
/// （描画は`pdfrx`＝PDFium。Webの`pdfium.wasm`はアプリに同梱し、外部へは通信しない。）
/// 開けなかった時（壊れている・パスワード付き等）は、案内とダウンロードへの導線を出す。
class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({required this.url, required this.fileName, super.key});

  final String url;
  final String fileName;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  final _pageController = PageController();
  int _page = 0;

  // 文書の参照は1度だけ作る（ページ送りの再ビルドで読み込み直さない）。
  late final PdfDocumentRef _documentRef = PdfDocumentRefUri(
    Uri.parse(widget.url),
  );

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    if (!await confirmDownload(context, ref, fileName: widget.fileName)) {
      return;
    }
    await launchUrl(
      Uri.parse(widget.url),
      mode: LaunchMode.externalApplication,
    );
  }

  void _goTo(int index, int count) {
    final target = index.clamp(0, count - 1);
    if (target == _page) return;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Widget _failure(Strings strings, ColorScheme colorScheme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.pdfOpenFailed,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _download,
            child: Text(strings.pdfDownloadAction),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    return PdfDocumentViewBuilder(
      documentRef: _documentRef,
      loadingBuilder: (context) => Scaffold(
        backgroundColor: Colors.transparent,
        // AppBarの裏まで本体を広げ、書面・画像を画面の縦中央に置く（2026-10-31）。
        extendBodyBehindAppBar: true,
        appBar: TapToCloseAppBar(
          onClose: () => Navigator.of(context).maybePop(),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            title: Text(widget.fileName),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      errorBuilder: (context, error, stackTrace) => Scaffold(
        backgroundColor: Colors.transparent,
        // AppBarの裏まで本体を広げ、書面・画像を画面の縦中央に置く（2026-10-31）。
        extendBodyBehindAppBar: true,
        appBar: TapToCloseAppBar(
          onClose: () => Navigator.of(context).maybePop(),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            title: Text(widget.fileName),
          ),
        ),
        body: _failure(strings, colorScheme),
      ),
      builder: (context, document) {
        if (document == null || document.pages.isEmpty) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            // AppBarの裏まで本体を広げ、書面・画像を画面の縦中央に置く（2026-10-31）。
            extendBodyBehindAppBar: true,
            appBar: TapToCloseAppBar(
              onClose: () => Navigator.of(context).maybePop(),
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                automaticallyImplyLeading: false,
                title: Text(widget.fileName),
              ),
            ),
            body: _failure(strings, colorScheme),
          );
        }
        final count = document.pages.length;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).maybePop(),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _goTo(_page + 1, count),
            const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                _goTo(_page + 1, count),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _goTo(_page - 1, count),
            const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                _goTo(_page - 1, count),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              // 背景は透明（ぼかしたメッセージ画面が透ける、[blurredViewerRoute]）。
              backgroundColor: Colors.transparent,
              // AppBarの裏まで本体を広げ、書面・画像を画面の縦中央に置く（2026-10-31）。
              extendBodyBehindAppBar: true,
              appBar: TapToCloseAppBar(
                onClose: () => Navigator.of(context).maybePop(),
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  // 戻る矢印は出さない（Esc・下スワイプ・戻る操作で閉じる）。
                  automaticallyImplyLeading: false,
                  actions: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('${_page + 1} / $count'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download),
                      tooltip: strings.downloadConfirmButton,
                      onPressed: _download,
                    ),
                  ],
                ),
              ),
              body: Stack(
                children: [
                  PinchPriorityPageView(
                    controller: _pageController,
                    // 隣のページを先に描画しておく（めくった時に白い書面のまま
                    // 待たされないように、2026-10-31）。
                    allowImplicitScrolling: true,
                    itemCount: count,
                    onPageChanged: (i) => setState(() => _page = i),
                    onDismiss: () => Navigator.of(context).maybePop(),
                    itemBuilder: (context, i) => _PdfPage(
                      document: document,
                      index: i,
                      onDismiss: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  // 縦の中央・左右の端の前後矢印（先頭は左、末尾は右を隠す）。
                  ViewerNavArrows(
                    index: _page,
                    count: count,
                    onPrevious: () => _goTo(_page - 1, count),
                    onNext: () => _goTo(_page + 1, count),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ビューアの1ページ分。ページ全体が画面に収まる大きさで出し、ピンチでズーム・
/// パンできる。ズームしてもぼやけないよう、画面に収めた大きさの2倍の解像度で
/// 描いて縮小して見せる。
class _PdfPage extends StatefulWidget {
  const _PdfPage({
    required this.document,
    required this.index,
    required this.onDismiss,
  });

  final PdfDocument document;
  final int index;

  /// 書面の外側（余白）をタップした時に閉じる。
  final VoidCallback onDismiss;

  @override
  State<_PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<_PdfPage> {
  final _transformationController = TransformationController();

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  /// 書面の外側のタップで閉じる。拡大中でも閉じる（パン・ピンチはタップとは
  /// 別のジェスチャーのため邪魔にならない、2026-10-31変更）。
  void _handleOutsideTap() => widget.onDismiss();

  @override
  Widget build(BuildContext context) {
    final page = widget.document.pages[widget.index];
    return LayoutBuilder(
      builder: (context, constraints) {
        // 上下左右に余白を取り、端にぴったり付かないようにする（バーの分も含む）。
        final scale = math.min(
          (constraints.maxWidth - 48) / page.width,
          (constraints.maxHeight - 128) / page.height,
        );
        final width = page.width * scale;
        final height = page.height * scale;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleOutsideTap,
          child: ZoomReporter(
            controller: _transformationController,
            child: InteractiveViewer(
              transformationController: _transformationController,
              maxScale: 5,
              child: SizedBox.expand(
                child: Center(
                  // 書面自身のタップは何もしない（外側のタップだけが閉じる）。
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: FittedBox(
                        child: SizedBox(
                          width: width * 2,
                          height: height * 2,
                          child: PdfPageView(
                            document: widget.document,
                            pageNumber: widget.index + 1,
                            // 描画が重くならないよう、解像度の上限を下げる
                            // （既定300dpi→144dpi。A4で約1200px幅）。
                            maximumDpi: 144,
                            // 既定のドロップシャドウは使わない（影は不使用の方針）。
                            decoration: const BoxDecoration(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
