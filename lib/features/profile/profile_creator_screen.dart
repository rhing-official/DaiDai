import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/profile_card.dart';
import '../../models/profile_material.dart';
import '../../providers/repository_providers.dart';

/// 和合: 蔵に登録した素材（アイコン・背景画像・ニックネーム・ステメ）を
/// 組み合わせて、最大[kMaxProfileCards]枚のプロフィールカードを作る画面。
/// カードの実際の利用場面（URL共有時の表示、友達バーのホバーポップアップなど）は
/// 別タスクで順次追加していく想定で、ここではまず作成・編集・削除のみを扱う。
class ProfileCreatorScreen extends ConsumerStatefulWidget {
  const ProfileCreatorScreen({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<ProfileCreatorScreen> createState() => _ProfileCreatorScreenState();
}

class _ProfileCreatorScreenState extends ConsumerState<ProfileCreatorScreen> {
  late AppUser _user;

  @override
  void initState() {
    super.initState();
    _user = widget.currentUser;
  }

  Future<void> _persist(AppUser updated) async {
    setState(() => _user = updated);
    try {
      await ref.read(userRepositoryProvider).updateUser(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
      );
    }
  }

  Future<void> _addCard() async {
    if (_user.profileCards.length >= kMaxProfileCards) return;
    final card = await showDialog<ProfileCard>(
      context: context,
      builder: (_) => _ProfileCardEditorDialog(user: _user),
    );
    if (card == null) return;
    await _persist(
      _user.copyWith(profileCards: [..._user.profileCards, card]),
    );
  }

  Future<void> _editCard(ProfileCard card) async {
    final updated = await showDialog<ProfileCard>(
      context: context,
      builder: (_) => _ProfileCardEditorDialog(user: _user, existing: card),
    );
    if (updated == null) return;
    await _persist(
      _user.copyWith(
        profileCards: [
          for (final c in _user.profileCards)
            if (c.id == card.id) updated else c,
        ],
      ),
    );
  }

  Future<void> _deleteCard(ProfileCard card) async {
    await _persist(
      _user.copyWith(
        profileCards: _user.profileCards.where((c) => c.id != card.id).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = _user.profileCards.length < kMaxProfileCards;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('和合'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '蔵に登録した素材を組み合わせて、プロフィールカードを作れます。'
            '最大3枚まで登録でき、相手に見せる場面ごとに使い分ける想定です。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          for (final card in _user.profileCards)
            _ProfileCardTile(
              user: _user,
              card: card,
              onTap: () => _editCard(card),
              onDelete: () => _deleteCard(card),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: canAdd ? _addCard : null,
            icon: const Icon(Icons.add),
            label: Text('プロフィールカードを作る（${_user.profileCards.length}/$kMaxProfileCards）'),
          ),
        ],
      ),
    );
  }
}

class _ProfileCardTile extends StatelessWidget {
  const _ProfileCardTile({
    required this.user,
    required this.card,
    required this.onTap,
    required this.onDelete,
  });

  final AppUser user;
  final ProfileCard card;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final icon = _find(user.icons, card.iconId);
    final nickname = _find(user.nicknames, card.nicknameId)?.text;
    final statusMessage = _find(user.statusMessages, card.statusMessageId)?.text;
    final subtitleParts = [
      if (nickname != null) nickname,
      if (statusMessage != null) statusMessage,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundImage: icon != null ? NetworkImage(icon.url) : null,
          child: icon == null ? const Icon(Icons.person) : null,
        ),
        title: Text(card.name),
        subtitle: Text(subtitleParts.isEmpty ? '未設定の素材があります' : subtitleParts.join(' / ')),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
      ),
    );
  }

  static T? _find<T>(List<T> items, String? id) {
    if (id == null) return null;
    for (final item in items) {
      final dynamic d = item;
      if (d.id == id) return item;
    }
    return null;
  }
}

class _ProfileCardEditorDialog extends StatefulWidget {
  const _ProfileCardEditorDialog({required this.user, this.existing});

  final AppUser user;
  final ProfileCard? existing;

  @override
  State<_ProfileCardEditorDialog> createState() => _ProfileCardEditorDialogState();
}

class _ProfileCardEditorDialogState extends State<_ProfileCardEditorDialog> {
  late final TextEditingController _nameController;
  String? _iconId;
  String? _backgroundImageId;
  String? _nicknameId;
  String? _statusMessageId;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _iconId = existing?.iconId;
    _backgroundImageId = existing?.backgroundImageId;
    _nicknameId = existing?.nicknameId;
    _statusMessageId = existing?.statusMessageId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final card = ProfileCard(
      id: widget.existing?.id ??
          '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}',
      name: name,
      iconId: _iconId,
      backgroundImageId: _backgroundImageId,
      nicknameId: _nicknameId,
      statusMessageId: _statusMessageId,
    );
    Navigator.of(context).pop(card);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'プロフィールカードを作る' : 'プロフィールカードを編集'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                maxLength: 20,
                decoration: const InputDecoration(labelText: 'カード名（自分用のラベル）'),
              ),
              _ImageChipPicker(
                label: 'アイコン',
                materials: widget.user.icons,
                selectedId: _iconId,
                onChanged: (id) => setState(() => _iconId = id),
              ),
              const SizedBox(height: 12),
              _ImageChipPicker(
                label: '背景画像',
                materials: widget.user.backgroundImages,
                selectedId: _backgroundImageId,
                onChanged: (id) => setState(() => _backgroundImageId = id),
              ),
              const SizedBox(height: 12),
              _TextChipPicker(
                label: 'ニックネーム',
                items: [for (final n in widget.user.nicknames) (n.id, n.text)],
                selectedId: _nicknameId,
                onChanged: (id) => setState(() => _nicknameId = id),
              ),
              const SizedBox(height: 12),
              _TextChipPicker(
                label: 'ステメ',
                items: [for (final m in widget.user.statusMessages) (m.id, m.text)],
                selectedId: _statusMessageId,
                onChanged: (id) => setState(() => _statusMessageId = id),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}

class _ImageChipPicker extends StatelessWidget {
  const _ImageChipPicker({
    required this.label,
    required this.materials,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final List<ProfileMaterial> materials;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              label: const Text('なし'),
              selected: selectedId == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final material in materials)
              ChoiceChip(
                avatar: CircleAvatar(backgroundImage: NetworkImage(material.url)),
                label: Text(material.id == selectedId ? '選択中' : '選ぶ'),
                selected: selectedId == material.id,
                onSelected: (_) => onChanged(material.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _TextChipPicker extends StatelessWidget {
  const _TextChipPicker({
    required this.label,
    required this.items,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final List<(String, String)> items;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              label: const Text('なし'),
              selected: selectedId == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final (id, text) in items)
              ChoiceChip(
                label: Text(text),
                selected: selectedId == id,
                onSelected: (_) => onChanged(id),
              ),
          ],
        ),
      ],
    );
  }
}
