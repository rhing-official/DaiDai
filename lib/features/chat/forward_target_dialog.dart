import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_ui_style.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../models/profile_card.dart' show ImageFocal;
import '../../providers/app_ui_style_provider.dart';
import '../../providers/block_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_providers.dart';
import '../../theme/block/block_theme.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../utils/forward_message.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/focal_circle_avatar.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/gekiga/gekiga_text_field.dart';
import '../../widgets/glass/glass_avatar.dart';
import '../../widgets/style_choice_chip.dart';
import 'talks_tab.dart' show BlockTalkTileWrap, dmSearchLabel;

/// この幅以上の画面では、右に転送内容のプレビューを置く2ペインにする。
const double _kForwardWideBreakpoint = 760;

/// 転送先（自分が参加している一対か、広場の寄合）を選ぶポップアップ（2026-11-05）。
/// 国の選択ダイアログと同じ、検索欄付きの作り。
///
/// 2026-11-06: 寄合を2段目の画面に分けず、広場の行の下に寄合を並べて直接選べる
/// （寄合が1つの広場は行を押すだけ）。検索は寄合の名前にも一致する。[preview]を渡し、
/// 画面が広い時は、右に転送内容のプレビューを出し、転送先を選んでから「転送」で確定する
/// （狭い時は従来どおり、選んだ瞬間に確定）。一対は寄合が複数でも最も古い寄合に送る
/// （通話履歴の送信と同じ扱い）。キャンセルはnull。
Future<ForwardTarget?> showForwardTargetDialog(
  BuildContext context, {
  required String currentUserId,
  ForwardPreview? preview,
}) {
  return showAppDialog<ForwardTarget>(
    context: context,
    builder: (_) =>
        _ForwardTargetDialog(currentUserId: currentUserId, preview: preview),
  );
}

class _ForwardTargetDialog extends ConsumerStatefulWidget {
  const _ForwardTargetDialog({required this.currentUserId, this.preview});

  final String currentUserId;
  final ForwardPreview? preview;

  @override
  ConsumerState<_ForwardTargetDialog> createState() =>
      _ForwardTargetDialogState();
}

class _ForwardTargetDialogState extends ConsumerState<_ForwardTargetDialog> {
  late final Future<List<DirectMessage>> _dms;
  late final Future<List<Group>> _groups;
  String _query = '';
  final _searchController = TextEditingController();

  /// 絞り込みチップの選択（語らいの検索と同じ、2026-11-06）。初期はどれも選ばれておらず
  /// （=全て表示）、1つでも選ぶとその種類だけに絞る。複数選択可、全て外すと元に戻る。
  bool _pickDms = false;
  bool _pickGroups = false;

  /// 寄合のチップ。選ぶと、広場の下に入れずに、寄合を1行ずつ（副題に広場名）並べる。
  bool _pickRooms = false;

  bool get _anyPick => _pickDms || _pickGroups || _pickRooms;
  bool get _showDms => !_anyPick || _pickDms;
  bool get _showGroups => !_anyPick || _pickGroups;

  /// 広場ごとの寄合（先に読み込んでおき、行の下に並べる・検索に使う）。
  final Map<String, List<Room>> _roomsByGroup = {};
  final Set<String> _expanded = {};

  /// 2ペインの時に選んだ転送先と、その表示名。
  ForwardTarget? _selected;
  String _selectedLabel = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _dms = ref
        .read(directMessageRepositoryProvider)
        .watchDirectMessages(widget.currentUserId)
        .first;
    _groups = ref
        .read(groupRepositoryProvider)
        .watchGroups(widget.currentUserId)
        .first;
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    final groups = await _groups;
    final repo = ref.read(groupRepositoryProvider);
    await Future.wait([
      for (final g in groups)
        repo
            .watchRooms(groupId: g.groupId, userId: widget.currentUserId)
            .first
            .then((rooms) => _roomsByGroup[g.groupId] = rooms)
            .catchError((Object _) => _roomsByGroup[g.groupId] = <Room>[]),
    ]);
    if (mounted) setState(() {});
  }

  bool _isWide(BuildContext context) =>
      widget.preview != null &&
      MediaQuery.sizeOf(context).width >= _kForwardWideBreakpoint;

  /// 転送先を決める。2ペインなら選択だけ（「転送」で確定）、そうでなければ閉じて返す。
  void _commit(ForwardTarget target, String label) {
    if (_isWide(context)) {
      setState(() {
        _selected = target;
        _selectedLabel = label;
      });
    } else {
      Navigator.of(context).pop(target);
    }
  }

  Future<void> _pickDm(DirectMessage dm, String label) async {
    final rooms = await ref
        .read(directMessageRepositoryProvider)
        .watchRooms(dmId: dm.dmId, userId: widget.currentUserId)
        .first;
    if (!mounted || rooms.isEmpty) return;
    final oldest = [...rooms]
      ..sort(
        (a, b) => (a.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
          b.createdAt?.millisecondsSinceEpoch ?? 0,
        ),
      );
    _commit(
      ForwardTarget(
        kind: ForwardTargetKind.dm,
        conversationId: dm.dmId,
        roomId: oldest.first.roomId,
      ),
      label,
    );
  }

  void _pickGroup(Group group) {
    final rooms = _roomsByGroup[group.groupId] ?? const <Room>[];
    if (rooms.isEmpty) return;
    if (rooms.length == 1) {
      _commit(
        ForwardTarget(
          kind: ForwardTargetKind.group,
          conversationId: group.groupId,
          roomId: rooms.first.roomId,
        ),
        group.name,
      );
      return;
    }
    setState(() {
      if (!_expanded.remove(group.groupId)) _expanded.add(group.groupId);
    });
  }

  void _pickRoom(Group group, Room room) => _commit(
    ForwardTarget(
      kind: ForwardTargetKind.group,
      conversationId: group.groupId,
      roomId: room.roomId,
    ),
    '${group.name} / ${room.name}',
  );

  bool _isSelected(String conversationId, [String? roomId]) {
    final s = _selected;
    if (s == null || s.conversationId != conversationId) return false;
    return roomId == null || s.roomId == roomId;
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    final blocked =
        ref.watch(blockedUserIdsProvider(widget.currentUserId)).value ??
        const <String>{};
    final query = _query.trim().toLowerCase();
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGlass = uiStyle == AppUiStyle.glass;
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final colorScheme = Theme.of(context).colorScheme;
    final wide = _isWide(context);

    // 劇画は、語らい一覧と同じ接合したモノクロボックス（`GekigaTileContent`）で、
    // 版画は太枠と硬い影の箱で描く。
    Widget tile({
      Widget? leading,
      required String title,
      String? subtitle,
      Widget? trailing,
      bool selected = false,
      bool indent = false,
      required VoidCallback onTap,
    }) {
      if (isGekiga) {
        // 1行ずつ独立した箱にして、寄合は箱ごと左へ余白を空ける（階層を見せる）。
        return Padding(
          padding: EdgeInsets.only(
            left: indent ? 28 : 0,
            bottom: GekigaJointedTileList.gap,
          ),
          child: GekigaJointedTileList(
            seeds: [title.hashCode],
            selectedFlags: [selected],
            children: [
              GekigaTileContent(
                selected: selected,
                leading: leading,
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: subtitle == null ? null : Text(subtitle),
                trailing: trailing,
                onTap: onTap,
              ),
            ],
          ),
        );
      }
      final isBlock = uiStyle == AppUiStyle.block;
      final listTile = ListTile(
        leading: leading,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: trailing,
        selected: selected && !isBlock,
        selectedTileColor: isGlass
            ? colorScheme.primary.withValues(alpha: 0.45)
            : colorScheme.primary,
        selectedColor: isGlass
            ? colorScheme.onSurfaceVariant
            : colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
      );
      // 版画は、語らい一覧の行と同じ太枠と硬い影の箱で囲む（他のスタイルはそのまま）。
      final box = isBlock
          ? BlockTalkTileWrap(selected: selected, child: listTile)
          : listTile;
      return indent
          ? Padding(padding: const EdgeInsets.only(left: 28), child: box)
          : box;
    }

    final list = FutureBuilder<List<Object>>(
      future: Future.wait<Object>([_dms, _groups]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final dms = snapshot.data![0] as List<DirectMessage>;
        final groups = snapshot.data![1] as List<Group>;
        final tiles = <Widget>[];
        for (final dm in _showDms ? dms : const <DirectMessage>[]) {
          final otherId = dm.otherUserId(widget.currentUserId);
          if (blocked.contains(otherId)) continue;
          final other = ref.watch(watchedUserProvider(otherId)).value;
          final label = dmSearchLabel(other, dm, widget.currentUserId);
          if (query.isNotEmpty && !label.toLowerCase().contains(query)) {
            continue;
          }
          tiles.add(
            tile(
              leading: _avatar(
                isGlass,
                colorScheme,
                other?.effectiveIconFor(dm.dmId)?.url,
                other?.effectiveIconFocalFor(dm.dmId),
                Icons.person,
                isGekiga: isGekiga,
              ),
              title: label,
              subtitle: vocab.dm,
              selected: _isSelected(dm.dmId),
              onTap: () => _pickDm(dm, label),
            ),
          );
        }
        for (final g in _showGroups ? groups : const <Group>[]) {
          final rooms = _roomsByGroup[g.groupId] ?? const <Room>[];
          final groupMatches = g.name.toLowerCase().contains(query);
          // 寄合機能をオフにした広場（単一モード）の寄合は利用者に見えない内部の1つなので、
          // 寄合名の検索には使わない。
          final roomMatches = [
            for (final r in g.roomsEnabled ? rooms : const <Room>[])
              if (query.isNotEmpty && r.name.toLowerCase().contains(query)) r,
          ];
          if (query.isNotEmpty && !groupMatches && roomMatches.isEmpty) {
            continue;
          }
          final multi = rooms.length > 1;
          final searchingRooms = query.isNotEmpty && roomMatches.isNotEmpty;
          final open =
              multi && (_expanded.contains(g.groupId) || searchingRooms);
          tiles.add(
            tile(
              leading: _avatar(
                isGlass,
                colorScheme,
                g.profileCard?.iconUrl,
                g.profileCard?.iconFocal,
                Icons.groups,
                isGekiga: isGekiga,
              ),
              title: g.name,
              subtitle: vocab.plaza,
              trailing: multi
                  ? Icon(open ? Icons.expand_less : Icons.expand_more)
                  : null,
              selected: !multi && _isSelected(g.groupId),
              onTap: () => _pickGroup(g),
            ),
          );
          if (open) {
            for (final r in searchingRooms ? roomMatches : rooms) {
              tiles.add(
                tile(
                  leading: const Icon(Icons.tag),
                  title: r.name,
                  indent: true,
                  selected: _isSelected(g.groupId, r.roomId),
                  onTap: () => _pickRoom(g, r),
                ),
              );
            }
          }
        }
        if (_pickRooms) {
          for (final g in groups) {
            // 寄合機能をオフにした広場は、寄合として並べない（広場の行から選ぶ）。
            if (!g.roomsEnabled) continue;
            final groupMatches = g.name.toLowerCase().contains(query);
            for (final r in _roomsByGroup[g.groupId] ?? const <Room>[]) {
              if (query.isNotEmpty &&
                  !groupMatches &&
                  !r.name.toLowerCase().contains(query)) {
                continue;
              }
              tiles.add(
                tile(
                  leading: const Icon(Icons.tag),
                  title: r.name,
                  subtitle: g.name,
                  selected: _isSelected(g.groupId, r.roomId),
                  onTap: () => _pickRoom(g, r),
                ),
              );
            }
          }
        }
        return _list(tiles, strings.forwardNoResults);
      },
    );

    final left = Column(
      // チップも一覧も左端に揃える（既定の中央寄せだとチップが中央に寄る）。
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isGekiga)
          GekigaTextField(
            controller: _searchController,
            autofocus: true,
            hintText: strings.forwardSearchHint,
            prefixIcon: const Icon(Icons.search, color: GekigaColors.onPanel),
            onChanged: (value) => setState(() => _query = value),
          )
        else
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: strings.forwardSearchHint,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        const SizedBox(height: 8),
        if (isGekiga)
          GekigaChoiceChipRow(
            labels: [vocab.dm, vocab.plaza, vocab.textChannel],
            selected: [_pickDms, _pickGroups, _pickRooms],
            onTap: (i) => setState(() {
              switch (i) {
                case 0:
                  _pickDms = !_pickDms;
                case 1:
                  _pickGroups = !_pickGroups;
                default:
                  _pickRooms = !_pickRooms;
              }
            }),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StyleChoiceChip(
                uiStyle: uiStyle,
                selected: _pickDms,
                onTap: () => setState(() => _pickDms = !_pickDms),
                labelBuilder: (fg) =>
                    Text(vocab.dm, style: TextStyle(color: fg)),
              ),
              StyleChoiceChip(
                uiStyle: uiStyle,
                selected: _pickGroups,
                onTap: () => setState(() => _pickGroups = !_pickGroups),
                labelBuilder: (fg) =>
                    Text(vocab.plaza, style: TextStyle(color: fg)),
              ),
              StyleChoiceChip(
                uiStyle: uiStyle,
                selected: _pickRooms,
                onTap: () => setState(() => _pickRooms = !_pickRooms),
                labelBuilder: (fg) =>
                    Text(vocab.textChannel, style: TextStyle(color: fg)),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Expanded(child: list),
      ],
    );

    return AlertDialog(
      // 2ペインの時は、テーマの既定の最大幅（劇画は400px）では2列が収まらないので広げる。
      constraints: wide
          ? const BoxConstraints(minWidth: 280, maxWidth: 840)
          : null,
      title: Text(strings.forwardDialogTitle),
      content: SizedBox(
        // 狭い画面では、ポップアップの左右の余白（AlertDialogの外側40×2＋内側24×2＝128px）と
        // 余裕16pxを除いた幅に収める（以前は112pxで、16pxはみ出していた）。
        width: wide
            ? 720
            : (MediaQuery.sizeOf(context).width - 144).clamp(200.0, 360.0),
        height: 440,
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 340, child: left),
                  const VerticalDivider(width: 33),
                  Expanded(
                    child: _PreviewPane(
                      preview: widget.preview!,
                      strings: strings,
                      uiStyle: uiStyle,
                      selectedLabel: _selected == null ? null : _selectedLabel,
                      onConfirm: _selected == null
                          ? null
                          : () => Navigator.of(context).pop(_selected),
                    ),
                  ),
                ],
              )
            : left,
      ),
    );
  }

  Widget _avatar(
    bool isGlass,
    ColorScheme colorScheme,
    String? url,
    ImageFocal? focal,
    IconData fallbackIcon, {
    bool isGekiga = false,
  }) {
    return isGlass
        ? GlassAvatar(
            size: 40,
            image: url != null ? NetworkImage(url) : null,
            focal: focal,
            fallback: url != null
                ? null
                : Icon(fallbackIcon, color: colorScheme.onSurfaceVariant),
          )
        : FocalCircleAvatar(
            url: url,
            focal: focal,
            foregroundColor: isGekiga
                ? GekigaColors.onPanel
                : colorScheme.onSurfaceVariant,
            fallback: Icon(fallbackIcon),
          );
  }

  Widget _list(List<Widget> tiles, String emptyLabel) {
    if (tiles.isEmpty) return Center(child: Text(emptyLabel));
    if (ref.watch(appUiStyleProvider) == AppUiStyle.gekiga) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: tiles,
        ),
      );
    }
    return ListView(children: tiles);
  }
}

/// 右ペイン。転送する内容のプレビューと、選んだ転送先・「転送」ボタン。
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.preview,
    required this.strings,
    required this.uiStyle,
    required this.selectedLabel,
    required this.onConfirm,
  });

  final ForwardPreview preview;
  final Strings strings;
  final AppUiStyle uiStyle;
  final String? selectedLabel;
  final VoidCallback? onConfirm;

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = uiStyle == AppUiStyle.gekiga
        ? GekigaColors.onPanel
        : scheme.onSurface;
    final text = preview.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (preview.stickerUrl != null)
          Image.network(preview.stickerUrl!, width: 120, height: 120),
        if (preview.media.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in preview.media)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: preview.media.length == 1 ? 200 : 88,
                    height: preview.media.length == 1 ? 150 : 88,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          m.url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(
                              m.isVideo ? Icons.videocam : Icons.image,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (m.isVideo)
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        for (final name in preview.files)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insert_drive_file_outlined, size: 18, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg),
                  ),
                ),
              ],
            ),
          ),
        if (text != null && text.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
              top: preview.media.isEmpty && preview.files.isEmpty ? 0 : 8,
            ),
            child: Text(text, style: TextStyle(color: fg)),
          ),
      ],
    );
  }

  Widget _card(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(width: double.infinity, child: _content(context)),
    );
    switch (uiStyle) {
      case AppUiStyle.gekiga:
        return GekigaJointedTileList(
          seeds: const [7],
          selectedFlags: const [false],
          children: [content],
        );
      case AppUiStyle.block:
        return blockMaterialBox(
          context,
          color: Theme.of(context).brightness == Brightness.light
              ? Colors.white
              : scheme.surface,
          child: content,
        );
      case AppUiStyle.glass:
      case AppUiStyle.flat:
        return DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: content,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: uiStyle == AppUiStyle.gekiga
          ? GekigaColors.onPanel.withValues(alpha: 0.75)
          : Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.forwardPreviewTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 6, bottom: 8),
            child: Align(alignment: Alignment.topLeft, child: _card(context)),
          ),
        ),
        const SizedBox(height: 8),
        if (selectedLabel == null)
          Text(strings.forwardChooseHint, style: hint)
        else ...[
          Text(
            '→ $selectedLabel',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: uiStyle == AppUiStyle.gekiga
                ? GekigaJointedTileList(
                    seeds: [strings.forwardConfirm.hashCode],
                    selectedFlags: const [true],
                    children: [
                      GekigaButton(
                        label: strings.forwardConfirm,
                        icon: Icons.send,
                        onPressed: onConfirm,
                      ),
                    ],
                  )
                : FilledButton.icon(
                    icon: const Icon(Icons.send, size: 18),
                    label: Text(strings.forwardConfirm),
                    onPressed: onConfirm,
                  ),
          ),
        ],
      ],
    );
  }
}
