import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/app_user.dart';
import '../../models/profile_material.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/user_repository.dart';

/// 身だしなみタブ（プロフィール設定・蔵システム）。
/// アイコン（最大[kMaxIcons]件）・背景画像（最大[kMaxBackgroundImages]件）・
/// ステメ（最大[kMaxStatusMessages]件）を蔵に保管し、その中から
/// 現在表示に使うものを選べる。
class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  late AppUser _user;
  bool _uploadingIcon = false;
  bool _uploadingBackground = false;

  @override
  void initState() {
    super.initState();
    _user = widget.currentUser;
  }

  UserRepository get _repository => ref.read(userRepositoryProvider);

  Future<void> _persist(AppUser updated) async {
    setState(() => _user = updated);
    try {
      await _repository.updateUser(updated);
    } catch (e) {
      _showError('保存に失敗しました: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAndUploadIcon() async {
    if (_user.icons.length >= kMaxIcons) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _uploadingIcon = true);
    try {
      final bytes = await picked.readAsBytes();
      final material = await _repository.uploadIcon(_user.userId, bytes);
      final updated = _user.copyWith(
        icons: [..._user.icons, material],
        activeIconId: _user.activeIconId ?? material.id,
      );
      await _persist(updated);
    } catch (e) {
      _showError('アイコンのアップロードに失敗しました: $e');
    } finally {
      if (mounted) setState(() => _uploadingIcon = false);
    }
  }

  Future<void> _pickAndUploadBackground() async {
    if (_user.backgroundImages.length >= kMaxBackgroundImages) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _uploadingBackground = true);
    try {
      final bytes = await picked.readAsBytes();
      final material =
          await _repository.uploadBackgroundImage(_user.userId, bytes);
      final updated = _user.copyWith(
        backgroundImages: [..._user.backgroundImages, material],
        activeBackgroundImageId: _user.activeBackgroundImageId ?? material.id,
      );
      await _persist(updated);
    } catch (e) {
      _showError('背景画像のアップロードに失敗しました: $e');
    } finally {
      if (mounted) setState(() => _uploadingBackground = false);
    }
  }

  Future<void> _deleteIcon(ProfileMaterial material) async {
    final remaining = _user.icons.where((m) => m.id != material.id).toList();
    final updated = _user.copyWith(
      icons: remaining,
      activeIconId: _user.activeIconId == material.id
          ? (remaining.isEmpty ? null : remaining.first.id)
          : _user.activeIconId,
    );
    await _persist(updated);
    try {
      await _repository.deleteProfileMaterial(material);
    } catch (e) {
      _showError('アイコンの削除に失敗しました: $e');
    }
  }

  Future<void> _deleteBackground(ProfileMaterial material) async {
    final remaining =
        _user.backgroundImages.where((m) => m.id != material.id).toList();
    final updated = _user.copyWith(
      backgroundImages: remaining,
      activeBackgroundImageId: _user.activeBackgroundImageId == material.id
          ? (remaining.isEmpty ? null : remaining.first.id)
          : _user.activeBackgroundImageId,
    );
    await _persist(updated);
    try {
      await _repository.deleteProfileMaterial(material);
    } catch (e) {
      _showError('背景画像の削除に失敗しました: $e');
    }
  }

  Future<void> _addStatusMessage() async {
    if (_user.statusMessages.length >= kMaxStatusMessages) return;
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _StatusMessageDialog(),
    );
    if (text == null || text.trim().isEmpty) return;

    final message = StatusMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}',
      text: text.trim(),
    );
    final updated = _user.copyWith(
      statusMessages: [..._user.statusMessages, message],
      activeStatusMessageId: _user.activeStatusMessageId ?? message.id,
    );
    await _persist(updated);
  }

  Future<void> _deleteStatusMessage(StatusMessage message) async {
    final remaining =
        _user.statusMessages.where((m) => m.id != message.id).toList();
    final updated = _user.copyWith(
      statusMessages: remaining,
      activeStatusMessageId: _user.activeStatusMessageId == message.id
          ? (remaining.isEmpty ? null : remaining.first.id)
          : _user.activeStatusMessageId,
    );
    await _persist(updated);
  }

  Future<void> _addNickname() async {
    if (_user.nicknames.length >= kMaxNicknames) return;
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _NicknameDialog(),
    );
    if (text == null || text.trim().isEmpty) return;

    final nickname = Nickname(
      id: '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}',
      text: text.trim(),
    );
    final updated = _user.copyWith(
      nicknames: [..._user.nicknames, nickname],
      activeNicknameId: _user.activeNicknameId ?? nickname.id,
    );
    await _persist(updated);
  }

  Future<void> _deleteNickname(Nickname nickname) async {
    final remaining =
        _user.nicknames.where((n) => n.id != nickname.id).toList();
    final updated = _user.copyWith(
      nicknames: remaining,
      activeNicknameId: _user.activeNicknameId == nickname.id
          ? (remaining.isEmpty ? null : remaining.first.id)
          : _user.activeNicknameId,
    );
    await _persist(updated);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              if (_user.activeNickname != null)
                Text(
                  _user.activeNickname!.text,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              if (_user.activeStatusMessage != null) ...[
                const SizedBox(height: 4),
                Text(
                  _user.activeStatusMessage!.text,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        _MaterialSection(
          title: 'アイコン',
          count: _user.icons.length,
          max: kMaxIcons,
          uploading: _uploadingIcon,
          onAdd: _pickAndUploadIcon,
          children: [
            for (final icon in _user.icons)
              _CircleMaterialThumb(
                url: icon.url,
                selected: icon.id == _user.activeIconId,
                onTap: () => _persist(_user.copyWith(activeIconId: icon.id)),
                onDelete: () => _deleteIcon(icon),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _MaterialSection(
          title: '背景画像',
          count: _user.backgroundImages.length,
          max: kMaxBackgroundImages,
          uploading: _uploadingBackground,
          onAdd: _pickAndUploadBackground,
          children: [
            for (final bg in _user.backgroundImages)
              _RectMaterialThumb(
                url: bg.url,
                selected: bg.id == _user.activeBackgroundImageId,
                onTap: () =>
                    _persist(_user.copyWith(activeBackgroundImageId: bg.id)),
                onDelete: () => _deleteBackground(bg),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _NicknameSection(
          nicknames: _user.nicknames,
          activeId: _user.activeNicknameId,
          onAdd: _addNickname,
          onSelect: (id) => _persist(_user.copyWith(activeNicknameId: id)),
          onDelete: _deleteNickname,
        ),
        const SizedBox(height: 24),
        _StatusMessageSection(
          messages: _user.statusMessages,
          activeId: _user.activeStatusMessageId,
          onAdd: _addStatusMessage,
          onSelect: (id) => _persist(_user.copyWith(activeStatusMessageId: id)),
          onDelete: _deleteStatusMessage,
        ),
      ],
    );
  }
}

/// アイコン・背景画像それぞれの蔵セクション（見出し＋件数＋サムネ一覧＋追加ボタン）。
class _MaterialSection extends StatelessWidget {
  const _MaterialSection({
    required this.title,
    required this.count,
    required this.max,
    required this.uploading,
    required this.onAdd,
    required this.children,
  });

  final String title;
  final int count;
  final int max;
  final bool uploading;
  final VoidCallback onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final canAdd = count < max && !uploading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title（$count/$max）',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ...children.map(
                (child) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: child,
                ),
              ),
              _AddThumbButton(enabled: canAdd, loading: uploading, onTap: onAdd),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddThumbButton extends StatelessWidget {
  const _AddThumbButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.add,
                    color: enabled
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  ),
          ),
        ),
      ),
    );
  }
}

class _CircleMaterialThumb extends StatelessWidget {
  const _CircleMaterialThumb({
    required this.url,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final String url;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              image: DecorationImage(
                image: NetworkImage(url),
                fit: BoxFit.cover,
              ),
              border: Border.all(
                color: selected ? accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          Positioned(
            right: -4,
            top: -4,
            child: _DeleteBadge(onTap: onDelete),
          ),
        ],
      ),
    );
  }
}

class _RectMaterialThumb extends StatelessWidget {
  const _RectMaterialThumb({
    required this.url,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final String url;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 128,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: NetworkImage(url),
                fit: BoxFit.cover,
              ),
              border: Border.all(
                color: selected ? accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          Positioned(
            right: -4,
            top: -4,
            child: _DeleteBadge(onTap: onDelete),
          ),
        ],
      ),
    );
  }
}

class _DeleteBadge extends StatelessWidget {
  const _DeleteBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.close, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}

class _StatusMessageSection extends StatelessWidget {
  const _StatusMessageSection({
    required this.messages,
    required this.activeId,
    required this.onAdd,
    required this.onSelect,
    required this.onDelete,
  });

  final List<StatusMessage> messages;
  final String? activeId;
  final VoidCallback onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<StatusMessage> onDelete;

  @override
  Widget build(BuildContext context) {
    final canAdd = messages.length < kMaxStatusMessages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ステメ（${messages.length}/$kMaxStatusMessages）',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        for (final message in messages)
          RadioGroup<String>(
            groupValue: activeId ?? '',
            onChanged: (value) {
              if (value != null) onSelect(value);
            },
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Radio<String>(value: message.id),
              title: Text(message.text),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(message),
              ),
            ),
          ),
        TextButton.icon(
          onPressed: canAdd ? onAdd : null,
          icon: const Icon(Icons.add),
          label: const Text('ステメを追加'),
        ),
      ],
    );
  }
}

class _NicknameSection extends StatelessWidget {
  const _NicknameSection({
    required this.nicknames,
    required this.activeId,
    required this.onAdd,
    required this.onSelect,
    required this.onDelete,
  });

  final List<Nickname> nicknames;
  final String? activeId;
  final VoidCallback onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<Nickname> onDelete;

  @override
  Widget build(BuildContext context) {
    final canAdd = nicknames.length < kMaxNicknames;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ニックネーム（${nicknames.length}/$kMaxNicknames）',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          '友達には、Rhing IDの代わりにここで選んだニックネームが表示されます。',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        for (final nickname in nicknames)
          RadioGroup<String>(
            groupValue: activeId ?? '',
            onChanged: (value) {
              if (value != null) onSelect(value);
            },
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Radio<String>(value: nickname.id),
              title: Text(nickname.text),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(nickname),
              ),
            ),
          ),
        TextButton.icon(
          onPressed: canAdd ? onAdd : null,
          icon: const Icon(Icons.add),
          label: const Text('ニックネームを追加'),
        ),
      ],
    );
  }
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog();

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ニックネームを追加'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        decoration: const InputDecoration(hintText: '友達に表示する呼び名を入力'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('追加'),
        ),
      ],
    );
  }
}

class _StatusMessageDialog extends StatefulWidget {
  const _StatusMessageDialog();

  @override
  State<_StatusMessageDialog> createState() => _StatusMessageDialogState();
}

class _StatusMessageDialogState extends State<_StatusMessageDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ステメを追加'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(hintText: 'ひとことを入力'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('追加'),
        ),
      ],
    );
  }
}
