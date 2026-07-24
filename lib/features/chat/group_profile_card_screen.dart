import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../models/group.dart';
import '../../models/group_profile_card.dart';
import '../../providers/repository_providers.dart';

/// 広場のプロフィールカード（1枚のみ）を作成・編集する画面。メンバー全員が
/// 編集できる（個人の工房カードと異なり、蔵の素材を参照せずアイコン・名前・
/// 説明を直接持つ自己完結型のカード）。
class GroupProfileCardScreen extends ConsumerStatefulWidget {
  const GroupProfileCardScreen({required this.group, super.key});

  final Group group;

  @override
  ConsumerState<GroupProfileCardScreen> createState() =>
      _GroupProfileCardScreenState();
}

class _GroupProfileCardScreenState
    extends ConsumerState<GroupProfileCardScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late GroupProfileCard _card;
  bool _uploadingIcon = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _card = widget.group.profileCard ??
        GroupProfileCard(name: widget.group.name);
    _nameController = TextEditingController(text: _card.name);
    _descriptionController = TextEditingController(text: _card.description);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _uploadingIcon = true);
    try {
      final bytes = await picked.readAsBytes();
      final groupRepository = ref.read(groupRepositoryProvider);
      final updated = await groupRepository.uploadProfileCardIcon(
        groupId: widget.group.groupId,
        card: _card,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() => _card = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ref.read(appStringsProvider).profileIconUploadError}: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingIcon = false);
      }
    }
  }

  Future<void> _save() async {
    final strings = ref.read(appStringsProvider);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.fieldRequiredError)));
      return;
    }

    setState(() => _saving = true);
    try {
      final card = _card.copyWith(
        name: name,
        description: _descriptionController.text.trim(),
      );
      await ref.read(groupRepositoryProvider).updateProfileCard(
            groupId: widget.group.groupId,
            card: card,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.groupProfileCardSaved)));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.profileSaveError}: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.groupProfileCardTitle),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(strings.groupProfileCardSave),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 56,
                  backgroundImage:
                      _card.iconUrl != null ? NetworkImage(_card.iconUrl!) : null,
                  child: _uploadingIcon
                      ? const CircularProgressIndicator()
                      : _card.iconUrl == null
                          ? const Icon(Icons.groups_outlined, size: 48)
                          : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: Theme.of(context).colorScheme.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _uploadingIcon ? null : _pickIcon,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.edit,
                          size: 18,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _uploadingIcon ? null : _pickIcon,
              child: Text(strings.groupProfileCardChangeIcon),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            maxLength: kMaxGroupProfileCardNameLength,
            decoration: InputDecoration(
              labelText: strings.groupProfileCardNameLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            maxLength: kMaxGroupProfileCardDescriptionLength,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: strings.groupProfileCardDescriptionLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
