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

  /// リンクURLに付与するキャッシュ回避用のクエリ値。招待URL自体は
  /// `groupId`のみで決まる固定文字列のため、外部サービス（Discord等）が
  /// カード編集より前に取得したプレビューをそのURL単位でキャッシュし続け、
  /// 何時間経っても古いカードのまま表示される問題があった。ダイアログを
  /// 開くたびに異なる値を付けることで、貼るたびに「新しいURL」として
  /// 扱われ、必ず最新のプレビューが再取得されるようにする（`groupId`部分は
  /// 変わらないため、アプリ内の`/join/:groupId`ルーティングやFirestore参照は
  /// この値を無視して問題なく動作する）。
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
    final link = buildWebLink('/join/$groupId?v=$cacheBust');
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
