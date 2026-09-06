import 'dart:typed_data';

import 'package:appflowy_editor/src/editor/util/file_picker/file_picker_service.dart';
import 'package:file_picker/file_picker.dart' as fp;

// DaiDai側の変更（2026-09-06）: file_picker v11.0.0でファイル選択APIが
// `FilePicker.platform.xxx()`（シングルトンインスタンス経由）から
// `FilePicker.xxx()`（静的メソッド直接呼び出し）へ全面刷新され、
// `.platform`アクセサ自体が廃止された。appflowy_editor 6.2.0
// （2025-12-08公開、file_picker v11.0.0より前）はこの変更に未対応のため、
// DaiDaiが使うfile_picker 12.x系のままではコンパイルできない
// （両APIが共存するバージョンは存在しない）。file_pickerをダウングレード
// せずに済ませるため、この1ファイルだけを新API向けに書き換えて
// `third_party/appflowy_editor/`にローカルで取り込んでいる
// （詳細はCLAUDE.md該当箇所、または`日記.md`参照）。
// なお`pickFiles`（`ImageUploadWidget`の「ローカルから選択」ボタン経由）
// 以外の2メソッドはDaiDai側では未使用（appflowy_editor内でも呼び出し
// 箇所が無い、到達しないコード）だが、コンパイルを通すため相当するAPIに
// 書き換えてある。appflowy_editorが新しいfile_pickerに対応した公式
// リリースを出したら、このディレクトリごと削除してpub.dev版に戻すこと。
class FilePicker implements FilePickerService {
  @override
  Future<String?> getDirectoryPath({String? title}) {
    return fp.FilePicker.getDirectoryPath(dialogTitle: title);
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    fp.FileType type = fp.FileType.any,
    List<String>? allowedExtensions,
    Function(fp.FilePickerStatus p1)? onFileLoading,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
  }) async {
    final files = await fp.FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
      onFileLoading: onFileLoading,
      allowMultiple: allowMultiple,
    );
    return FilePickerResult(files);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    fp.FileType type = fp.FileType.any,
    List<String>? allowedExtensions,
    bool lockParentWindow = false,
  }) async {
    final uri = await fp.FilePicker.saveFile(
      fileName: fileName ?? 'untitled',
      bytes: Uint8List(0),
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
    );
    return uri?.toFilePath();
  }
}
