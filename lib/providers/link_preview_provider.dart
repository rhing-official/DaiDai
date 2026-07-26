import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/link_preview.dart';
import 'repository_providers.dart';

/// URLごとのリンクプレビュー取得結果をキャッシュする。同じURLを含む
/// メッセージが並んでいても、Riverpodのfamilyキャッシュにより1回しか
/// 取得しに行かない。
final linkPreviewProvider =
    FutureProvider.family<LinkPreview?, String>((ref, url) {
  return ref.watch(linkPreviewRepositoryProvider).fetchPreview(url);
});
