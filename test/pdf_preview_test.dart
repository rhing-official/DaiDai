import 'package:daidai/widgets/pdf_viewer_screen.dart';
import 'package:daidai/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MessageFileMetadata meta({
    String extension = 'pdf',
    String mimeType = 'application/pdf',
    int size = 1000,
  }) => MessageFileMetadata(
    url: 'https://example.com/a.pdf',
    fileName: 'a.$extension',
    extension: extension,
    sizeBytes: size,
    mimeType: mimeType,
  );

  test('PDFは拡張子またはMIMEで判定し、大きすぎるものは除く', () {
    expect(isPreviewablePdf(meta()), isTrue);
    expect(
      isPreviewablePdf(
        meta(extension: 'PDF', mimeType: 'application/octet-stream'),
      ),
      isTrue,
    );
    expect(
      isPreviewablePdf(meta(extension: 'bin', mimeType: 'application/pdf')),
      isTrue,
    );
    expect(
      isPreviewablePdf(meta(extension: 'txt', mimeType: 'text/plain')),
      isFalse,
    );
    expect(isPreviewablePdf(meta(size: 60 * 1024 * 1024)), isFalse);
  });
}
