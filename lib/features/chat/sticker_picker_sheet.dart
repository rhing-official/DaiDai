import 'package:flutter/material.dart';

import '../../models/sticker.dart';
import 'sticker_picker_content.dart';

/// 所有しているペタピタを選んで送信するボトムシート（技術仕様書7.4参照、
/// 2026-08-11追加、2026-08-11に検索・パック別レール対応の
/// `StickerPickerContent`利用へ刷新）。daidai横丁が無い現段階では
/// 入手経路が無いため、所有ペタピタはFirebaseコンソールから手動投入した
/// ものに限られる（0件時は空状態を表示する）。タップで選択し、選ばれた
/// [Sticker]でこのシート自身をpopする（呼び出し元の[Navigator.pop]相当、
/// `showModalBottomSheet`の戻り値として受け取る）。見出しテキストは
/// 表示しない（2026-08-12、ミニマルな見た目を目指す方針）。
class StickerPickerSheet extends StatelessWidget {
  const StickerPickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 420,
        child: StickerPickerContent(
          railAxis: Axis.horizontal,
          onStickerSelected: (sticker) => Navigator.of(context).pop(sticker),
        ),
      ),
    );
  }
}
