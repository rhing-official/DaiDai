import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/sticker.dart';
import '../../models/sticker_send_mode.dart';
import '../../providers/repository_providers.dart';
import '../../providers/sticker_send_mode_provider.dart';

/// ペタピタピッカーの本体（検索バー＋パック別レール＋グリッド、2026-08-11
/// 追加）。モバイル用ボトムシート（`StickerPickerSheet`）とデスクトップ用
/// アンカーポップアップ（`sticker_picker_popup.dart`）の両方から共有される。
/// [railAxis]で、パック切り替えレールを左サイド（`Axis.vertical`）に
/// 出すか下部（`Axis.horizontal`）に出すかを切り替える。
class StickerPickerContent extends ConsumerStatefulWidget {
  const StickerPickerContent({
    required this.railAxis,
    required this.onStickerSelected,
    super.key,
  });

  final Axis railAxis;
  final void Function(Sticker sticker) onStickerSelected;

  @override
  ConsumerState<StickerPickerContent> createState() =>
      _StickerPickerContentState();
}

class _StickerPickerContentState extends ConsumerState<StickerPickerContent> {
  String _query = '';
  // nullは「すべて」タブを表す。
  String? _selectedPackId;

  // LINE型送信方式の拡大プレビュー用（2026-08-13追加）。
  Sticker? _pendingPreviewSticker;
  Offset? _pendingTapGlobalPos;
  Offset? _lastTapDownGlobalPos;
  OverlayEntry? _previewEntry;

  @override
  void dispose() {
    // ピッカー自体が閉じられた（ボトムシートのスワイプ・ポップアップ外
    // タップ等）際に、挿入済みのOverlayEntryがルートOverlayに残り続ける
    // リークを防ぐ。
    _previewEntry?.remove();
    super.dispose();
  }

  void _handleStickerTap(Sticker sticker, StickerSendMode mode) {
    if (mode == StickerSendMode.discord) {
      widget.onStickerSelected(sticker);
      return;
    }
    // LINE型: 直前にプレビュー中だったのと同じペタピタの2回目タップなら送信。
    if (_pendingPreviewSticker?.stickerId == sticker.stickerId) {
      _removePreview();
      widget.onStickerSelected(sticker);
      return;
    }
    // 1回目のタップ、または別のペタピタへの差し替え。
    _pendingPreviewSticker = sticker;
    _pendingTapGlobalPos = _lastTapDownGlobalPos;
    if (_previewEntry == null) {
      _previewEntry = OverlayEntry(builder: (_) => _buildPreviewOverlay());
      Overlay.of(context).insert(_previewEntry!);
    } else {
      _previewEntry!.markNeedsBuild();
    }
  }

  void _removePreview() {
    _previewEntry?.remove();
    _previewEntry = null;
    _pendingPreviewSticker = null;
    _pendingTapGlobalPos = null;
  }

  Widget _buildPreviewOverlay() {
    final sticker = _pendingPreviewSticker;
    final anchor = _pendingTapGlobalPos;
    if (sticker == null || anchor == null) return const SizedBox.shrink();

    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final screenSize = overlayBox.size;
    const previewSize = 180.0;
    const screenPad = 8.0;
    final left = (anchor.dx - previewSize / 2).clamp(
      screenPad,
      screenSize.width - previewSize - screenPad,
    );
    final top = (anchor.dy - previewSize - 24).clamp(
      screenPad,
      screenSize.height - previewSize - screenPad,
    );

    return Positioned(
      left: left,
      top: top,
      width: previewSize,
      height: previewSize,
      child: GestureDetector(
        // 拡大プレビュー自体をタップ＝「同じペタピタをもう一度タップ」と同義。
        onTap: () => _handleStickerTap(sticker, StickerSendMode.line),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          elevation: 8,
          shadowColor: Theme.of(context).colorScheme.shadow,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Image.network(
              sticker.imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final currentUserId = ref.watch(authStateProvider).value?.uid;
    final sendMode = ref.watch(stickerSendModeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: strings.stickerSearchHint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: currentUserId == null
              ? const SizedBox.shrink()
              : StreamBuilder<List<StickerPack>>(
                  stream: ref
                      .watch(stickerRepositoryProvider)
                      .watchOwnedPacks(currentUserId),
                  builder: (context, snapshot) {
                    final packs = snapshot.data ?? const <StickerPack>[];
                    final content = _buildGrid(strings, packs, sendMode);
                    if (packs.isEmpty) return content;
                    final rail = _buildRail(packs);
                    return widget.railAxis == Axis.vertical
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              rail,
                              const VerticalDivider(width: 1),
                              Expanded(child: content),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: content),
                              const Divider(height: 1),
                              rail,
                            ],
                          );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRail(List<StickerPack> packs) {
    final items = <({String? packId, String imageUrl})>[
      (packId: null, imageUrl: packs.first.stickers.first.imageUrl),
      for (final pack in packs)
        if (pack.stickers.isNotEmpty)
          (packId: pack.packId, imageUrl: pack.stickers.first.imageUrl),
    ];
    final railChildren = [
      for (final item in items)
        _RailIcon(
          imageUrl: item.imageUrl,
          selected: _selectedPackId == item.packId,
          isAllTab: item.packId == null,
          onTap: () => setState(() => _selectedPackId = item.packId),
        ),
    ];
    if (widget.railAxis == Axis.vertical) {
      return SizedBox(
        width: 56,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: railChildren,
        ),
      );
    }
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: railChildren,
      ),
    );
  }

  Widget _buildGrid(
    Strings strings,
    List<StickerPack> packs,
    StickerSendMode mode,
  ) {
    final selectedPackId = _selectedPackId;
    final query = _query.trim().toLowerCase();
    final stickers = packs
        .where(
          (pack) => selectedPackId == null || pack.packId == selectedPackId,
        )
        .expand((pack) => pack.stickers)
        .where(
          (sticker) =>
              query.isEmpty || sticker.name.toLowerCase().contains(query),
        )
        .toList();
    if (stickers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            strings.chatNoStickersMessage,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, index) {
        final sticker = stickers[index];
        return InkWell(
          onTapDown: (details) =>
              _lastTapDownGlobalPos = details.globalPosition,
          onTap: () => _handleStickerTap(sticker, mode),
          child: Image.network(
            sticker.imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
          ),
        );
      },
    );
  }
}

class _RailIcon extends StatelessWidget {
  const _RailIcon({
    required this.imageUrl,
    required this.selected,
    required this.isAllTab,
    required this.onTap,
  });

  final String imageUrl;
  final bool selected;
  final bool isAllTab;
  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.all(4),
          child: ClipOval(
            child: isAllTab
                ? Icon(
                    Icons.apps,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  )
                : Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined, size: 20),
                  ),
          ),
        ),
      ),
    );
  }
}
