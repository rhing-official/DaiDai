import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_ui_style.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/block_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_providers.dart';
import '../../utils/forward_message.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/focal_circle_avatar.dart';
import '../../models/profile_card.dart' show ImageFocal;
import '../../widgets/glass/glass_avatar.dart';
import '../../widgets/style_choice_chip.dart';
import 'talks_tab.dart' show dmSearchLabel;

/// 転送先（自分が参加している一対か、広場の寄合）を選ぶポップアップ（2026-11-05）。
/// 国の選択ダイアログと同じ、検索欄付きの作り。広場は寄合が複数ある時だけ、2段目で寄合を選ぶ。
/// 一対は寄合が複数でも最も古い寄合に送る（通話履歴の送信と同じ扱い）。キャンセルはnull。
Future<ForwardTarget?> showForwardTargetDialog(
  BuildContext context, {
  required String currentUserId,
}) {
  return showAppDialog<ForwardTarget>(
    context: context,
    builder: (_) => _ForwardTargetDialog(currentUserId: currentUserId),
  );
}

class _ForwardTargetDialog extends ConsumerStatefulWidget {
  const _ForwardTargetDialog({required this.currentUserId});

  final String currentUserId;

  @override
  ConsumerState<_ForwardTargetDialog> createState() =>
      _ForwardTargetDialogState();
}

class _ForwardTargetDialogState extends ConsumerState<_ForwardTargetDialog> {
  late final Future<List<DirectMessage>> _dms;
  late final Future<List<Group>> _groups;
  String _query = '';

  /// 一覧に出す種類（一対・広場）。初期は両方。両方オフにはならない。
  bool _showDms = true;
  bool _showGroups = true;

  /// 寄合を選ぶ段階の広場（nullなら会話の一覧）。
  Group? _pickingRoomOf;

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
  }

  Future<void> _pickDm(DirectMessage dm) async {
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
    Navigator.of(context).pop(
      ForwardTarget(
        kind: ForwardTargetKind.dm,
        conversationId: dm.dmId,
        roomId: oldest.first.roomId,
      ),
    );
  }

  Future<void> _pickGroup(Group group) async {
    final rooms = await ref
        .read(groupRepositoryProvider)
        .watchRooms(groupId: group.groupId, userId: widget.currentUserId)
        .first;
    if (!mounted || rooms.isEmpty) return;
    if (rooms.length == 1) {
      Navigator.of(context).pop(
        ForwardTarget(
          kind: ForwardTargetKind.group,
          conversationId: group.groupId,
          roomId: rooms.first.roomId,
        ),
      );
      return;
    }
    setState(() {
      _pickingRoomOf = group;
      _query = '';
      _rooms = rooms;
    });
  }

  List<Room> _rooms = const [];

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    final blocked =
        ref.watch(blockedUserIdsProvider(widget.currentUserId)).value ??
        const <String>{};
    final query = _query.trim().toLowerCase();
    final picking = _pickingRoomOf;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGlass = uiStyle == AppUiStyle.glass;
    final colorScheme = Theme.of(context).colorScheme;

    Widget list;
    if (picking != null) {
      final filtered = [
        for (final r in _rooms)
          if (query.isEmpty || r.name.toLowerCase().contains(query)) r,
      ];
      list = _list([
        for (final r in filtered)
          ListTile(
            title: Text(r.name),
            onTap: () => Navigator.of(context).pop(
              ForwardTarget(
                kind: ForwardTargetKind.group,
                conversationId: picking.groupId,
                roomId: r.roomId,
              ),
            ),
          ),
      ], strings.forwardNoResults);
    } else {
      list = FutureBuilder<List<Object>>(
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
              ListTile(
                leading: _avatar(
                  isGlass,
                  colorScheme,
                  other?.effectiveIconFor(dm.dmId)?.url,
                  other?.effectiveIconFocalFor(dm.dmId),
                  Icons.person,
                ),
                title: Text(label),
                subtitle: Text(vocab.dm),
                onTap: () => _pickDm(dm),
              ),
            );
          }
          for (final g in _showGroups ? groups : const <Group>[]) {
            if (query.isNotEmpty && !g.name.toLowerCase().contains(query)) {
              continue;
            }
            tiles.add(
              ListTile(
                leading: _avatar(
                  isGlass,
                  colorScheme,
                  g.profileCard?.iconUrl,
                  g.profileCard?.iconFocal,
                  Icons.groups,
                ),
                title: Text(g.name),
                subtitle: Text(vocab.plaza),
                onTap: () => _pickGroup(g),
              ),
            );
          }
          return _list(tiles, strings.forwardNoResults);
        },
      );
    }

    return AlertDialog(
      title: Text(picking?.name ?? strings.forwardDialogTitle),
      content: SizedBox(
        width: 360,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: strings.forwardSearchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            if (picking == null) ...[
              Row(
                children: [
                  StyleChoiceChip(
                    uiStyle: uiStyle,
                    selected: _showDms,
                    onTap: () => setState(() {
                      _showDms = !_showDms;
                      if (!_showDms && !_showGroups) _showGroups = true;
                    }),
                    labelBuilder: (fg) =>
                        Text(vocab.dm, style: TextStyle(color: fg)),
                  ),
                  const SizedBox(width: 8),
                  StyleChoiceChip(
                    uiStyle: uiStyle,
                    selected: _showGroups,
                    onTap: () => setState(() {
                      _showGroups = !_showGroups;
                      if (!_showDms && !_showGroups) _showDms = true;
                    }),
                    labelBuilder: (fg) =>
                        Text(vocab.plaza, style: TextStyle(color: fg)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Expanded(child: list),
          ],
        ),
      ),
      actions: [
        if (picking != null)
          TextButton(
            onPressed: () => setState(() {
              _pickingRoomOf = null;
              _query = '';
            }),
            child: Text(strings.forwardBack),
          ),
      ],
    );
  }

  Widget _avatar(
    bool isGlass,
    ColorScheme colorScheme,
    String? url,
    ImageFocal? focal,
    IconData fallbackIcon,
  ) {
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
            foregroundColor: colorScheme.onSurfaceVariant,
            fallback: Icon(fallbackIcon),
          );
  }

  Widget _list(List<Widget> tiles, String emptyLabel) {
    if (tiles.isEmpty) return Center(child: Text(emptyLabel));
    return ListView(children: tiles);
  }
}
