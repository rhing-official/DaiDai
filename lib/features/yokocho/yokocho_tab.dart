import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/creator_profile.dart';
import '../../models/sticker.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/home_tab_swipe.dart';
import '../../widgets/sticker_image.dart';
import 'yokocho_providers.dart';

enum _YokochoFilter { all, owned, favourites, cart }

/// ホームの「横丁」タブ（2026-11-28）。ぺったんの閲覧・検索・所持・お気に入り・カートを、
/// アプリの中で扱う。詳細は、`Navigator.push`でなく、このタブの中の表示の切り替えで出す
/// （広い画面でサイドバーまで覆わないため。`AlbumPaneView`などと同じ作り）。
/// 購入・出品・審査は、ここには作らない。
class YokochoTab extends ConsumerStatefulWidget {
  const YokochoTab({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<YokochoTab> createState() => _YokochoTabState();
}

class _YokochoTabState extends ConsumerState<YokochoTab> {
  _YokochoFilter _filter = _YokochoFilter.all;
  String _query = '';
  String? _openPackId;
  Map<String, CreatorProfile> _creators = const {};
  Set<String> _requestedCreators = {};

  Future<void> _loadCreators(List<StickerPack> packs) async {
    final missing = {
      for (final pack in packs)
        if (!_requestedCreators.contains(pack.creatorId)) pack.creatorId,
    };
    if (missing.isEmpty) return;
    _requestedCreators = {..._requestedCreators, ...missing};
    final loaded = await ref
        .read(yokochoRepositoryProvider)
        .loadCreators(missing);
    if (!mounted) return;
    setState(() => _creators = {..._creators, ...loaded});
  }

  String get _uid => widget.currentUser.userId;

  Future<void> _toggleFavourite(String packId, bool on) async {
    try {
      await ref
          .read(yokochoRepositoryProvider)
          .setFavourite(_uid, packId, on: on);
    } catch (e) {
      if (mounted) showAutoDismissBanner(context, message: '$e');
    }
  }

  Future<void> _toggleCart(String packId, bool on) async {
    try {
      await ref.read(yokochoRepositoryProvider).setCart(_uid, packId, on: on);
    } catch (e) {
      if (mounted) showAutoDismissBanner(context, message: '$e');
    }
  }

  Future<void> _acquire(List<StickerPack> packs) async {
    final strings = ref.read(appStringsProvider);
    final repository = ref.read(yokochoRepositoryProvider);
    var failed = false;
    for (final pack in packs) {
      try {
        await repository.acquireFree(pack.packId);
        // 入手したら、カートから外す。
        await repository.setCart(_uid, pack.packId, on: false);
      } catch (_) {
        failed = true;
      }
    }
    if (!mounted) return;
    showAutoDismissBanner(
      context,
      message: failed ? strings.yokochoAcquireFailed : strings.yokochoAcquired,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final catalog = ref.watch(yokochoCatalogProvider);
    final owned = ref.watch(yokochoOwnedIdsProvider).value ?? const {};
    final favourites = ref.watch(yokochoFavouriteIdsProvider).value ?? const {};
    final cart = ref.watch(yokochoCartIdsProvider).value ?? const {};

    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (packs) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadCreators(packs);
        });
        final open = _openPackId == null
            ? null
            : packs.where((p) => p.packId == _openPackId).firstOrNull;
        if (open != null) {
          return _PackDetail(
            pack: open,
            creator: _creators[open.creatorId],
            owned: owned.contains(open.packId),
            favourite: favourites.contains(open.packId),
            inCart: cart.contains(open.packId),
            onBack: () => setState(() => _openPackId = null),
            onFavourite: (on) => _toggleFavourite(open.packId, on),
            onCart: (on) => _toggleCart(open.packId, on),
            onAcquire: () => _acquire([open]),
          );
        }

        final visible = _applyFilter(packs, owned, favourites, cart);
        final freeInCart = [
          for (final pack in packs)
            if (cart.contains(pack.packId) &&
                !owned.contains(pack.packId) &&
                pack.price <= 0 &&
                pack.deleteScheduledAt == null)
              pack,
        ];
        return HomeTabSwipe(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: strings.yokochoSearchHint,
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final filter in _YokochoFilter.values)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(_filterLabel(strings, filter)),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_filter == _YokochoFilter.cart && freeInCart.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: () => _acquire(freeInCart),
                        child: Text(strings.yokochoAcquireAllFree),
                      ),
                    ),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(child: Text(strings.yokochoEmpty))
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 200,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.82,
                              ),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final pack = visible[index];
                            return _PackCard(
                              pack: pack,
                              creator: _creators[pack.creatorId],
                              owned: owned.contains(pack.packId),
                              onTap: () =>
                                  setState(() => _openPackId = pack.packId),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<StickerPack> _applyFilter(
    List<StickerPack> packs,
    Set<String> owned,
    Set<String> favourites,
    Set<String> cart,
  ) {
    final query = _query.trim().toLowerCase();
    return [
      for (final pack in packs)
        if (switch (_filter) {
              _YokochoFilter.all => true,
              _YokochoFilter.owned => owned.contains(pack.packId),
              _YokochoFilter.favourites => favourites.contains(pack.packId),
              _YokochoFilter.cart => cart.contains(pack.packId),
            } &&
            (query.isEmpty ||
                pack.name.toLowerCase().contains(query) ||
                pack.tags.any((tag) => tag.toLowerCase().contains(query)) ||
                (_creators[pack.creatorId]?.nickname ?? '')
                    .toLowerCase()
                    .contains(query)))
          pack,
    ];
  }

  String _filterLabel(Strings strings, _YokochoFilter filter) =>
      switch (filter) {
        _YokochoFilter.all => strings.yokochoFilterAll,
        _YokochoFilter.owned => strings.yokochoFilterOwned,
        _YokochoFilter.favourites => strings.yokochoFilterFavourites,
        _YokochoFilter.cart => strings.yokochoFilterCart,
      };
}

class _PackCard extends ConsumerWidget {
  const _PackCard({
    required this.pack,
    required this.creator,
    required this.owned,
    required this.onTap,
  });

  final StickerPack pack;
  final CreatorProfile? creator;
  final bool owned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final cover = pack.cover;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: cover == null
                    ? const SizedBox.shrink()
                    : StickerImage(cover.imageUrl, cacheWidth: 320),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              pack.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              creator?.nickname ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
            ),
            if (owned)
              Text(
                strings.yokochoOwnedBadge,
                style: const TextStyle(fontSize: 12),
              )
            else if (pack.price <= 0)
              Text(strings.yokochoFree, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _PackDetail extends ConsumerWidget {
  const _PackDetail({
    required this.pack,
    required this.creator,
    required this.owned,
    required this.favourite,
    required this.inCart,
    required this.onBack,
    required this.onFavourite,
    required this.onCart,
    required this.onAcquire,
  });

  final StickerPack pack;
  final CreatorProfile? creator;
  final bool owned;
  final bool favourite;
  final bool inCart;
  final VoidCallback onBack;
  final ValueChanged<bool> onFavourite;
  final ValueChanged<bool> onCart;
  final VoidCallback onAcquire;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final ending = pack.deleteScheduledAt != null;
    final canAcquire = !owned && !ending && pack.price <= 0;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
              Expanded(
                child: Text(
                  pack.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                tooltip: favourite
                    ? strings.yokochoRemoveFavourite
                    : strings.yokochoAddFavourite,
                icon: Icon(favourite ? Icons.favorite : Icons.favorite_border),
                onPressed: () => onFavourite(!favourite),
              ),
              if (!owned)
                IconButton(
                  tooltip: inCart
                      ? strings.yokochoRemoveCart
                      : strings.yokochoAddCart,
                  icon: Icon(
                    inCart
                        ? Icons.shopping_cart
                        : Icons.add_shopping_cart_outlined,
                  ),
                  onPressed: () => onCart(!inCart),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      if (creator?.nickname != null) creator!.nickname!,
                      if (owned) strings.yokochoOwnedBadge,
                      if (!owned && pack.price <= 0) strings.yokochoFree,
                      if (ending) strings.yokochoEnding,
                    ].join('  '),
                  ),
                ),
                if (canAcquire)
                  FilledButton(
                    onPressed: onAcquire,
                    child: Text(strings.yokochoAcquire),
                  ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 110,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: pack.stickers.length,
              itemBuilder: (context, index) =>
                  StickerImage(pack.stickers[index].imageUrl, cacheWidth: 240),
            ),
          ),
        ],
      ),
    );
  }
}
