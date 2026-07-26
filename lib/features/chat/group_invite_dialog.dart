import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/strings.dart';
import '../../utils/web_link.dart';

/// 広場への招待リンク・QRコードを表示するダイアログ。縁結び（個人の招待リンク）
/// と同じ考え方で、リンクをコピーできるほか、外部SNSにリンクを貼ってもカードが
/// 見えるようにするOGP対応は`groupInvites/{groupId}`（公開読み取り可能な
/// プレビュー用ドキュメント）を通じて別途行う。
class GroupInviteDialog extends ConsumerWidget {
  const GroupInviteDialog({
    required this.groupId,
    required this.cacheBust,
    super.key,
  });

  final String groupId;

  /// リンクURLに付与するキャッシュ回避用の値。招待URL自体は`groupId`のみで
  /// 決まる固定文字列のため、外部サービス（Discord等）がカード編集より前に
  /// 取得したプレビューをそのURL単位でキャッシュし続け、何時間経っても古い
  /// カードのまま表示される問題があった。クエリパラメータ（`?v=...`）で
  /// 試したところ、Discordはクエリ部分を無視してキャッシュキーを正規化する
  /// らしく効果が無かった（実機検証で、異なる`?v=`値の3件が全く同じ古い
  /// プレビューのまま変わらないことを確認）。そのためパスの末尾セグメントに
  /// 埋め込む方式に変更した（`/join/:groupId/:cacheBust`、`app_router.dart`
  /// 参照）。ダイアログを開くたびに異なる値を付けることで、貼るたびに
  /// 「新しいURL」として扱われ、必ず最新のプレビューが再取得されるように
  /// する（`groupId`部分は変わらないため、アプリ内のルーティングや
  /// Firestore参照はこの値を無視して問題なく動作する）。
  final int cacheBust;

  static Future<void> show(BuildContext context, String groupId) {
    return showDialog<void>(
      context: context,
      builder: (_) => GroupInviteDialog(
        groupId: groupId,
        cacheBust: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final link = buildWebLink('/join/$groupId/$cacheBust');
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(strings.groupInviteDialogTitle),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.groupInviteDialogDescription),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(child: SelectableText(link, maxLines: 1)),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined),
                    tooltip: strings.enmusubiCopyLink,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: QrImageView(data: link, size: 180),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
