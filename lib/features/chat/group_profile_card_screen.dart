import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../models/group.dart';
import '../../models/group_profile_card.dart';
import '../../providers/repository_providers.dart';

/// 広場のプロフィールカード（1枚のみ）を作成・編集する画面。メンバー全員が
/// 編集できる（個人の工房カードと異なり、蔵の素材を参照せずアイコン・名前・
/// 説明を直接持つ自己完結型のカード）。カードのプレビューは個人の工房カード
/// （`_WorkshopCardSlot`、`lib/features/profile/profile_tab.dart`）と同じ見た目
/// （背景画像＋グラデーション＋アイコン＋太字の名前＋説明）で表示する
/// （2026-07-25、個人カードとデザインを揃える要望により変更）。
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
  bool _uploadingBackground = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _card = widget.group.profileCard ??
        GroupProfileCard(name: widget.group.name);
    _nameController = TextEditingController(text: _card.name)
      ..addListener(_onTextChanged);
    _descriptionController = TextEditingController(text: _card.description)
      ..addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // カードのプレビューは名前・説明の入力にあわせてその場で更新する
  // （個人の工房カードのズーム編集画面が入力内容を即座にカードへ反映するのと
  // 同じ体験にするため）。
  void _onTextChanged() {
    setState(() {
      _card = _card.copyWith(
        name: _nameController.text,
        description: _descriptionController.text,
      );
    });
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

  Future<void> _pickBackground() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _uploadingBackground = true);
    try {
      final bytes = await picked.readAsBytes();
      final groupRepository = ref.read(groupRepositoryProvider);
      final updated = await groupRepository.uploadProfileCardBackground(
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
        setState(() => _uploadingBackground = false);
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
    final colorScheme = Theme.of(context).colorScheme;
    final width = (MediaQuery.sizeOf(context).width * 0.8).clamp(240.0, 360.0);
    final height = width * 1.25;
    final background = _card.backgroundImageUrl;
    final hasBackground = background != null;
    final avatarRadius = (width * 0.11).clamp(18.0, 44.0);
    final padding = (width * 0.075).clamp(12.0, 28.0);
    final nameFontSize = (width * 0.09).clamp(14.0, 24.0);
    final descriptionFontSize = (width * 0.055).clamp(11.0, 16.0);

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
            child: SizedBox(
              width: width,
              height: height,
              child: Material(
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.circular(16),
                color: colorScheme.surfaceContainerHighest,
                // 個人の工房カード（_WorkshopCardSlot）と同じ構成: 背景画像レイヤー
                // （タップで変更）→ 暗転グラデーション（装飾のみ、IgnorePointerで
                // ヒットテスト対象から外す）→ アイコン・名前・説明のレイヤー。
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _uploadingBackground ? null : _pickBackground,
                      child: background != null
                          ? Image.network(background, fit: BoxFit.cover)
                          : ColoredBox(color: colorScheme.surfaceContainerHighest),
                    ),
                    if (hasBackground)
                      const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black54],
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.all(padding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: _uploadingIcon ? null : _pickIcon,
                            child: CircleAvatar(
                              radius: avatarRadius,
                              backgroundImage: _card.iconUrl != null
                                  ? NetworkImage(_card.iconUrl!)
                                  : null,
                              child: _uploadingIcon
                                  ? const CircularProgressIndicator()
                                  : _card.iconUrl == null
                                      ? const Icon(Icons.groups_outlined)
                                      : null,
                            ),
                          ),
                          SizedBox(height: padding * 0.6),
                          Text(
                            _card.name.isEmpty
                                ? strings.groupProfileCardNameLabel
                                : _card.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: nameFontSize,
                              fontWeight: FontWeight.bold,
                              color: hasBackground ? Colors.white : null,
                            ),
                          ),
                          if (_card.description.isNotEmpty)
                            Text(
                              _card.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: descriptionFontSize,
                                color: hasBackground
                                    ? Colors.white70
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_uploadingBackground)
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                strings.groupProfileCardChangeBackground,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
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
