import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/sticker.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../models/sticker_send_mode.dart';
import '../../providers/recent_stickers_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/sticker_send_mode_provider.dart';

/// ぺったんピッカーの本体（検索バー＋パック別レール＋グリッド、2026-08-11
/// 追加）。モバイル用ボトムシート（`StickerPickerSheet`）とデスクトップ用
/// アンカーポップアップ（`sticker_picker_popup.dart`）の両方から共有される。
/// [railAxis]で、パック切り替えレールを左サイド（`Axis.vertical`）に
/// 出すか下部（`Axis.horizontal`）に出すかを切り替える。
/// 「最近使った」タブを表す[StickerPickerContent]内部のタブid。
const _kRecentTab = '__recent__';

class StickerPickerContent extends ConsumerStatefulWidget {
  const StickerPickerContent({
    required this.railAxis,
    required this.onStickerSelected,
    this.initialPackId,
    super.key,
  });

  final Axis railAxis;
  final void Function(Sticker sticker) onStickerSelected;

  /// 指定時は「すべて」タブではなく、このパックに絞り込んだ状態で開く
  /// （他人が送信済みのぺったんをタップして開く導線用、2026-08-14追加）。
  final String? initialPackId;

  @override
  ConsumerState<StickerPickerContent> createState() =>
      _StickerPickerContentState();
}

class _StickerPickerContentState extends ConsumerState<StickerPickerContent> {
  String _query = '';
  // nullは「すべて」タブを表す。[_kRecentTab]は「最近使った」タブ。
  String? _chosenPackId;
  // 利用者がタブを選んだか。選ぶまでは[_selectedPackId]が既定（指定パック、
  // 無ければ最近があれば「最近」、無ければ「すべて」）を返す。最近の読み込みは
  // 非同期のため、初期化時ではなく都度判定する（2026-10-29）。
  bool _tabChosen = false;

  String? get _selectedPackId {
    if (_tabChosen) return _chosenPackId;
    if (widget.initialPackId != null) return widget.initialPackId;
    return ref.read(recentStickersProvider).isNotEmpty ? _kRecentTab : null;
  }

  void _selectTab(String? packId) => setState(() {
    _tabChosen = true;
    _chosenPackId = packId;
  });

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
    // LINE型: 直前にプレビュー中だったのと同じぺったんの2回目タップなら送信。
    if (_pendingPreviewSticker?.stickerId == sticker.stickerId) {
      _removePreview();
      widget.onStickerSelected(sticker);
      return;
    }
    // 1回目のタップ、または別のぺったんへの差し替え。
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
    const screenPad = 8.0;
    // ピッカー本体（ポップアップ・ボトムシート）の矩形。プレビューはこの真上に
    // 出し、選んでいるぺったん一覧を隠さない（2026-10-29）。上に十分な余白が
    // 無い時だけ、従来どおりタップ位置の近くに重ねる。
    final pickerBox = context.findRenderObject() as RenderBox?;
    final pickerRect = (pickerBox != null && pickerBox.hasSize)
        ? pickerBox.localToGlobal(Offset.zero) & pickerBox.size
        : null;
    final roomAbove = pickerRect == null
        ? 0.0
        : pickerRect.top - screenPad * 2 - 8;
    final above = roomAbove >= 160;
    final previewSize = above ? math.min(320.0, roomAbove) : 240.0;
    final maxLeft = math.max(
      screenPad,
      screenSize.width - previewSize - screenPad,
    );
    final maxTop = math.max(
      screenPad,
      screenSize.height - previewSize - screenPad,
    );
    final left = ((above ? pickerRect!.center.dx : anchor.dx) - previewSize / 2)
        .clamp(screenPad, maxLeft);
    final top =
        (above
                ? pickerRect!.top - previewSize - 8
                : anchor.dy - previewSize - 24)
            .clamp(screenPad, maxTop);

    return Positioned(
      left: left,
      top: top,
      width: previewSize,
      height: previewSize,
      child: GestureDetector(
        // 拡大プレビュー自体をタップ＝「同じぺったんをもう一度タップ」と同義。
        onTap: () => _handleStickerTap(sticker, StickerSendMode.line),
        child: Material(
          // 劇画UIでは、黒ではなく劇画の背景色（アクセント）にする（2026-10-29）。
          color: ref.watch(appUiStyleProvider) == AppUiStyle.gekiga
              ? Theme.of(context).colorScheme.surface
              : Theme.of(context).colorScheme.surfaceContainerHigh,
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
    // 最近の読み込み完了で、既定のタブを見直すため購読する。
    ref.watch(recentStickersProvider);

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
      _RailIcon(
        imageUrl: '',
        selected: _selectedPackId == _kRecentTab,
        isAllTab: false,
        icon: Icons.history,
        tooltip: ref.read(appStringsProvider).stickerRecentTab,
        onTap: () => _selectTab(_kRecentTab),
      ),
      for (final item in items)
        _RailIcon(
          imageUrl: item.imageUrl,
          selected: _selectedPackId == item.packId,
          isAllTab: item.packId == null,
          onTap: () => _selectTab(item.packId),
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
    final List<Sticker> source;
    if (selectedPackId == _kRecentTab) {
      // 所持パック内のぺったんを、最近使った順に並べる（所持していない・削除
      // 済みのものは出さない）。
      final byId = {
        for (final pack in packs)
          for (final sticker in pack.stickers) sticker.stickerId: sticker,
      };
      source = [
        for (final id in ref.watch(recentStickersProvider))
          if (byId[id] != null) byId[id]!,
      ];
    } else {
      source = packs
          .where(
            (pack) => selectedPackId == null || pack.packId == selectedPackId,
          )
          .expand((pack) => pack.stickers)
          .toList();
    }
    final stickers = source
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
    this.icon,
    this.tooltip,
  });

  /// 指定時は画像の代わりにこのアイコンを出す（「最近使った」タブ）。
  final IconData? icon;
  final String? tooltip;

  final String imageUrl;
  final bool selected;
  final bool isAllTab;
  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = Padding(
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
            child: (isAllTab || icon != null)
                ? Icon(
                    icon ?? Icons.apps,
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
    return tooltip == null ? item : Tooltip(message: tooltip!, child: item);
  }
}
