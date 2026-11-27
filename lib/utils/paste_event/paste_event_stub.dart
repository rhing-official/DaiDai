import 'pasted_file.dart';

Future<String?> readPasteEventText({
  Duration timeout = const Duration(milliseconds: 800),
}) async => null;

/// Web以外では、ファイルの貼り付けを受け取る手段が無いため、何もしない。
void Function() listenPasteFiles(
  void Function(List<PastedFile> files) onFiles,
) => () {};
