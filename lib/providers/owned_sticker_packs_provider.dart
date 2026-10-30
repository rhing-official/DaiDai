import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sticker.dart';
import 'repository_providers.dart';

/// [userId]が所有しているぺったんパックの一覧（2026-10-30追加）。以前はぺったん
/// ピッカーが再ビルドのたびにStreamを作り直し、そのたびに`stickerPacks`カタログ
/// 全件を取り直していて重かったため、購読を1本にして保持する（2回目以降に
/// ピッカーを開いても取り直さない。所有が変わった時だけ更新される）。
final ownedStickerPacksProvider =
    StreamProvider.family<List<StickerPack>, String>((ref, userId) {
      return ref.watch(stickerRepositoryProvider).watchOwnedPacks(userId);
    });
