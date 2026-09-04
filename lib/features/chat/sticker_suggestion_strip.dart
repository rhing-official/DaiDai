import 'package:flutter/material.dart';

import '../../models/sticker.dart';

/// メッセージ内容に応じたペタピタ提案の横並び表示（2026-09-05追加、
/// `lib/utils/sticker_suggestion.dart`の`suggestStickers`が返す候補を
/// 入力欄のすぐ上に表示する）。LINEの「おすすめスタンプ」がタップした
/// 時点でそのまま確定・送信される挙動（競合調査.md 2026-09-05付エントリ
/// 参照）に合わせ、通常のペタピタピッカー（`StickerPickerContent`）が持つ
/// LINE型2タップ・プレビュー挙動（`stickerSendMode`設定）とは独立に、
/// ここではタップ即送信にしている。
class StickerSuggestionStrip extends StatelessWidget {
  const StickerSuggestionStrip({
    required this.stickers,
    required this.onStickerTap,
    super.key,
  });

  final List<Sticker> stickers;
  final void Function(Sticker sticker) onStickerTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: stickers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final sticker = stickers[index];
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onStickerTap(sticker),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Image.network(
                sticker.imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
          );
        },
      ),
    );
  }
}
