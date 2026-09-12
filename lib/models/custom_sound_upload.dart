/// 端末に記憶している、着信音・呼出音・通知音のカスタムアップロード音源
/// （2026-09-12追加）。`fileName`は表示用の元ファイル名で、既にカスタム
/// 音源が有効なのにこの記憶がまだ無かったケースをバックフィルした場合は
/// nullになりうる（その場合は呼び出し側で既定ラベルにフォールバックする）。
class CustomSoundUpload {
  const CustomSoundUpload({required this.url, this.fileName});

  final String url;
  final String? fileName;
}
