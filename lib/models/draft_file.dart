/// 入力欄の下書きに添えたファイル（送信前のトレイの1件、2026-11-27）。他の端末の入力欄へ
/// 同期する為に、サーバーへ一時的に保存する。URLは持たず、保存先のパスだけを持つ
/// （保存先を変えても、全件を書き換えずに済む）。
class DraftFile {
  const DraftFile({
    required this.id,
    required this.name,
    required this.contentType,
    required this.path,
    required this.size,
  });

  final String id;
  final String name;

  /// file | image | video
  final String contentType;

  /// 保存先のパス。
  final String path;
  final int size;

  factory DraftFile.fromJson(Map<String, dynamic> json) => DraftFile(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    contentType: json['contentType'] as String? ?? 'file',
    path: json['path'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'contentType': contentType,
    'path': path,
    'size': size,
  };
}

/// 下書きのファイルを同期する1件の大きさの上限（バイト）。超えるものは、その端末の入力欄だけに残す。
/// `storage.rules`の`draftFiles`と同じ値。
const int kMaxDraftFileSyncBytes = 10 * 1024 * 1024;
