import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/strings.dart';
import '../../models/group_profile_card.dart';
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
  /// 参照）。
  ///
  /// 値は現在時刻ではなく、プロフィールカードの内容（名前・一言・アイコン・
  /// 背景画像URL）から決定的に計算したハッシュにしている。当初は
  /// ダイアログを開くたびに現在時刻を使っていたが、それだとカードを
  /// 編集していなくても毎回「新しいURL」扱いになり、OGP画像生成
  /// （`api/og-image.mjs`、フォント取得等で数秒かかる）がVercelの
  /// キャッシュを一切使えず開くたびに毎回フルで走ってしまい、体感速度の
  /// 悪化に繋がっていた。カード内容が変わらない限り同じ値になるため、
  /// 未編集のまま何度貼っても同じURL＝キャッシュが効き、編集した時だけ
  /// 新しい値になって正しく再取得される。
  final String cacheBust;

  static String _cacheBustFor(GroupProfileCard? card) {
    if (card == null) return 'none';
    final source =
        '${card.name}|${card.description}|${card.iconUrl}|${card.backgroundImageUrl}';
    // URLのパスセグメントに使うため、短い16進数のダイジェストにする
    // （衝突しても実害は「編集していないのに新しいURLになる」程度で、
    // キャッシュ効率が多少落ちるだけなので短縮して問題ない）。
    return md5.convert(utf8.encode(source)).toString().substring(0, 12);
  }

  static Future<void> show(
    BuildContext context,
    String groupId,
    GroupProfileCard? profileCard,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => GroupInviteDialog(
        groupId: groupId,
        cacheBust: _cacheBustFor(profileCard),
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
