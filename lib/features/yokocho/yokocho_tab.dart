import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/creator_profile.dart';
import '../../models/sticker.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/yokocho.dart';
import '../../widgets/fixed_font_theme.dart';
import '../../widgets/home_tab_swipe.dart';
import '../../widgets/sticker_image.dart';
import 'yokocho_palette.dart';
import 'yokocho_providers.dart';

enum _YokochoFilter { all, owned, favourites, cart }

/// 横丁のDart版の画面（2026-11-28）。WebViewが使えないWeb版のアプリで使う。
/// Android・iOSは、横丁のWebをそのまま開く`YokochoTab`（`yokocho_webview_tab.dart`）。
///
/// ホームの「横丁」タブ（2026-11-28）。ぺったんの閲覧・検索・所持・お気に入り・カートを、
/// アプリの中で扱う。詳細は、`Navigator.push`でなく、このタブの中の表示の切り替えで出す
/// （広い画面でサイドバーまで覆わないため。`AlbumPaneView`などと同じ作り）。
/// 購入・出品・審査は、ここには作らない。
class YokochoNativeTab extends ConsumerStatefulWidget {
  const YokochoNativeTab({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<YokochoNativeTab> createState() => _YokochoNativeTabState();
}

class _YokochoNativeTabState extends ConsumerState<YokochoNativeTab> {
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

    final palette = YokochoPalette.of(context);
    return FixedFontTheme(
      child: Material(
        color: palette.surface,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: palette.onSurface),
          child: _buildBody(
            context,
            strings,
            palette,
            catalog,
            owned,
            favourites,
            cart,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    Strings strings,
    YokochoPalette palette,
    AsyncValue<List<StickerPack>> catalog,
    Set<String> owned,
    Set<String> favourites,
    Set<String> cart,
  ) {
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
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                    child: Center(
                      child: Text(
                        'daidai横丁',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 3,
                          color: palette.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child: _SearchField(
                      palette: palette,
                      hint: strings.yokochoSearchHint,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        for (final filter in _YokochoFilter.values)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _FilterChip(
                              palette: palette,
                              label: _filterLabel(strings, filter),
                              active: _filter == filter,
                              onTap: () => setState(() => _filter = filter),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_filter == _YokochoFilter.cart && freeInCart.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _PillButton(
                          palette: palette,
                          label: strings.yokochoAcquireAllFree,
                          onTap: () => _acquire(freeInCart),
                        ),
                      ),
                    ),
                  ),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        strings.yokochoEmpty,
                        style: TextStyle(color: palette.subtle),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 360,
                            mainAxisSpacing: 24,
                            crossAxisSpacing: 24,
                            mainAxisExtent: 330,
                          ),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final pack = visible[index];
                        return _PackCard(
                          pack: pack,
                          creator: _creators[pack.creatorId],
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

/// 横丁の検索欄。丸い角、白に近い面、細い縁。
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.palette,
    required this.hint,
    required this.onChanged,
  });

  final YokochoPalette palette;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: palette.card.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.glassEdge.withValues(alpha: 0.8)),
      ),
      child: TextField(
        onChanged: onChanged,
        style: TextStyle(fontSize: 14, color: palette.onSurfaceVariant),
        cursorColor: palette.primary,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: 14, color: palette.outline),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

/// 横丁の絞り込みのチップ（`PackFilterPanel`の`Chip`）。
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.palette,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final YokochoPalette palette;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? palette.primary : palette.card.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? palette.primary
                : palette.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: active ? palette.onPrimary : palette.primary,
          ),
        ),
      ),
    );
  }
}

/// 横丁の丸いボタン。主は青の塗り、副は縁だけ。
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.palette,
    required this.label,
    required this.onTap,
    this.filled = true,
    this.icon,
  });

  final YokochoPalette palette;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? palette.onPrimary : palette.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: filled ? palette.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: filled ? null : Border.all(color: palette.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _priceLabel(Strings strings, StickerPack pack) {
  if (pack.price <= 0) return strings.yokochoFree;
  // ストア版は、Webの価格を併記しない（ストアの誘導の禁止）。
  if (!yokochoLinksAllowed()) return '';
  return '¥${pack.price.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
}

class _CreatorRow extends StatelessWidget {
  const _CreatorRow({
    required this.palette,
    required this.creator,
    required this.size,
    required this.fontSize,
    required this.color,
  });

  final YokochoPalette palette;
  final CreatorProfile? creator;
  final double size;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final creator = this.creator;
    if (creator == null) return const SizedBox.shrink();
    final icon = creator.iconUrl;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipOval(
          child: icon == null
              ? Container(
                  width: size,
                  height: size,
                  color: palette.outlineVariant,
                )
              : Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: palette.glassEdge.withValues(alpha: 0.8),
                    ),
                  ),
                  child: ClipOval(
                    child: Image.network(
                      icon,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Container(color: palette.outlineVariant),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            creator.nickname ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fontSize, color: color),
          ),
        ),
      ],
    );
  }
}

/// 横丁のカード（`StickerPackCard`）。白い面、細い縁、角丸16、4対3の画像、価格・名前・出品者・種別。
class _PackCard extends ConsumerWidget {
  const _PackCard({
    required this.pack,
    required this.creator,
    required this.onTap,
  });

  final StickerPack pack;
  final CreatorProfile? creator;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final palette = YokochoPalette.of(context);
    final cover = pack.cover;
    final price = _priceLabel(strings, pack);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: palette.card,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              border: Border.all(color: palette.outlineVariant),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: cover == null
                        ? Center(
                            child: Text(
                              strings.yokochoNoImage,
                              style: TextStyle(
                                fontSize: 14,
                                color: palette.outline,
                              ),
                            ),
                          )
                        : StickerImage(cover.imageUrl, cacheWidth: 480),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (price.isNotEmpty)
                        Text(
                          price,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: pack.price <= 0
                                ? palette.free
                                : palette.paid,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        pack.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: palette.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: _CreatorRow(
                    palette: palette,
                    creator: creator,
                    size: 20,
                    fontSize: 12,
                    color: palette.subtle,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (pack.category.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: palette.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            pack.category,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1,
                              color: palette.onPrimaryContainer,
                            ),
                          ),
                        ),
                      for (final tag in pack.tags.take(3))
                        Text(
                          '#$tag',
                          style: TextStyle(
                            fontSize: 10,
                            color: palette.outline,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 横丁のぺったん詳細（`[packId]/page.tsx`）。画像、名前、出品者、価格、操作、商品情報の並び。
class _PackDetail extends ConsumerStatefulWidget {
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
  ConsumerState<_PackDetail> createState() => _PackDetailState();
}

class _PackDetailState extends ConsumerState<_PackDetail> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final palette = YokochoPalette.of(context);
    final pack = widget.pack;
    final ending = pack.deleteScheduledAt != null;
    final canAcquire = !widget.owned && !ending && pack.price <= 0;
    final price = _priceLabel(strings, pack);
    final selected = pack.stickers
        .where((s) => s.stickerId == _selectedId)
        .firstOrNull;
    final shown = selected ?? pack.cover;
    final created = pack.createdAt?.toDate();

    Widget infoRow(String label, String value) => Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: palette.subtle),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: palette.onSurface),
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: palette.onSurfaceVariant),
              onPressed: widget.onBack,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.outlineVariant),
            ),
            padding: const EdgeInsets.all(24),
            child: AspectRatio(
              aspectRatio: 1.2,
              child: shown == null
                  ? const SizedBox.shrink()
                  : StickerImage(shown.imageUrl, cacheWidth: 800),
            ),
          ),
          if (pack.stickers.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sticker in pack.stickers)
                  GestureDetector(
                    onTap: () =>
                        setState(() => _selectedId = sticker.stickerId),
                    child: Container(
                      width: 64,
                      height: 64,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: palette.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sticker.stickerId == shown?.stickerId
                              ? palette.primary
                              : palette.outlineVariant,
                        ),
                      ),
                      child: StickerImage(sticker.imageUrl, cacheWidth: 160),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          if (pack.category.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                pack.category,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2,
                  color: palette.subtle,
                ),
              ),
            ),
          Text(
            pack.name,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.5,
              color: palette.onSurface,
            ),
          ),
          if (widget.creator != null) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: _CreatorRow(
                palette: palette,
                creator: widget.creator,
                size: 28,
                fontSize: 14,
                color: palette.onSurfaceVariant,
              ),
            ),
          ],
          if (price.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              price,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w500,
                color: pack.price <= 0 ? palette.free : palette.paid,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (canAcquire)
                _PillButton(
                  palette: palette,
                  label: strings.yokochoAcquire,
                  onTap: widget.onAcquire,
                ),
              if (widget.owned)
                _PillButton(
                  palette: palette,
                  label: strings.yokochoOwnedBadge,
                  filled: false,
                  icon: Icons.check,
                  onTap: () {},
                ),
              _PillButton(
                palette: palette,
                filled: false,
                icon: widget.favourite ? Icons.favorite : Icons.favorite_border,
                label: widget.favourite
                    ? strings.yokochoRemoveFavourite
                    : strings.yokochoAddFavourite,
                onTap: () => widget.onFavourite(!widget.favourite),
              ),
              if (!widget.owned)
                _PillButton(
                  palette: palette,
                  filled: false,
                  icon: widget.inCart
                      ? Icons.shopping_cart
                      : Icons.add_shopping_cart_outlined,
                  label: widget.inCart
                      ? strings.yokochoRemoveCart
                      : strings.yokochoAddCart,
                  onTap: () => widget.onCart(!widget.inCart),
                ),
            ],
          ),
          if (ending)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                strings.yokochoEnding,
                style: TextStyle(fontSize: 12, color: palette.subtle),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            '・${strings.yokochoNoteUse}',
            style: TextStyle(fontSize: 12, height: 1.6, color: palette.subtle),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: palette.outlineVariant)),
            ),
            child: Column(
              children: [
                infoRow(strings.yokochoInfoCount, '${pack.stickers.length}'),
                if (pack.category.isNotEmpty)
                  infoRow(strings.yokochoInfoCategory, pack.category),
                if (created != null)
                  infoRow(
                    strings.yokochoInfoPublished,
                    '${created.year}/${created.month.toString().padLeft(2, '0')}/${created.day.toString().padLeft(2, '0')}',
                  ),
                if (pack.tags.isNotEmpty)
                  infoRow(
                    strings.yokochoInfoTags,
                    pack.tags.map((t) => '#$t').join('  '),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
