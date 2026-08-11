import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../models/group.dart';
import '../../models/group_profile_card.dart';
import '../../providers/repository_providers.dart';

/// 広場のプロフィールカード（1枚のみ）を作成・編集するポップアップの中身。
/// メンバー全員が編集できる（個人の工房カードと異なり、蔵の素材を参照せず
/// 背景画像URL・アイコンURL・広場名・一言を直接持つ自己完結型のカード）。
/// 操作感は個人の工房カードのズーム編集画面（`_CardZoomEditor`、
/// `lib/features/profile/profile_tab.dart`）に合わせてある: カード内の
/// 名前・一言をタップするとその場でテキスト編集用の小さなポップアップが開き、
/// 変更する度に自動保存する（保存ボタンは無い）。背景・アイコンも同様に
/// タップした場所から直接画像を選ぶ。閉じるボタンも置かず、呼び出し元
/// （`_showProfileCardPopup`、`chat_panes.dart`）のバリアタップに委ねる。
class GroupProfileCardPopup extends ConsumerStatefulWidget {
  const GroupProfileCardPopup({required this.group, super.key});

  final Group group;

  @override
  ConsumerState<GroupProfileCardPopup> createState() =>
      _GroupProfileCardPopupState();
}

class _GroupProfileCardPopupState extends ConsumerState<GroupProfileCardPopup> {
  late GroupProfileCard _card;
  bool _uploadingIcon = false;
  bool _uploadingBackground = false;
  final _editController = TextEditingController();

  // 個人の工房カード編集画面（`_CardZoomEditorState._pendingPersist`）と同じ
  // 理由で、保存呼び出しをFutureチェーンで直列化する。自動保存は短い間隔で
  // 連続して呼ばれうる（アイコン変更直後に一言も変更する等）ため、直列化
  // しないとFirestore側の更新が競合する恐れがある。
  Future<void> _pendingPersist = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _card =
        widget.group.profileCard ?? GroupProfileCard(name: widget.group.name);
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  Future<void> _persist() {
    final card = _card;
    final next = _pendingPersist.then((_) async {
      try {
        await ref
            .read(groupRepositoryProvider)
            .updateProfileCard(groupId: widget.group.groupId, card: card);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${ref.read(appStringsProvider).profileSaveError}: $e',
              ),
            ),
          );
        }
      }
    });
    _pendingPersist = next;
    return next;
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
      await _persist();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${ref.read(appStringsProvider).profileIconUploadError}: $e',
          ),
        ),
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
      await _persist();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${ref.read(appStringsProvider).profileIconUploadError}: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingBackground = false);
      }
    }
  }

  /// 名前・一言をその場で編集する小さなテキスト入力ポップアップを開く。
  /// 個人の工房カードは蔵にある既存の素材（ニックネーム等）から選ぶだけだが、
  /// 広場のカードは自由入力のため、代わりにテキストボックスをポップアップで
  /// 出す。Enterキー確定・ポップアップ外タップでの終了いずれの場合も、
  /// 閉じた時点の入力内容を読み取って変更があれば自動保存する。
  Future<void> _editField({
    required String label,
    required String currentValue,
    required int maxLength,
    required void Function(String value) onChanged,
  }) async {
    _editController.text = currentValue;
    _editController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: currentValue.length,
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: _editController,
          autofocus: true,
          maxLength: maxLength,
          onSubmitted: (_) => Navigator.of(context).pop(),
        ),
      ),
    );
    final newValue = _editController.text.trim();
    if (newValue == currentValue) return;
    onChanged(newValue);
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    const width = 280.0;
    const height = width * 1.25;
    final background = _card.backgroundImageUrl;
    final hasBackground = background != null;
    const avatarRadius = 32.0;
    const padding = 20.0;
    const nameFontSize = 20.0;
    const descriptionFontSize = 14.0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(16),
          color: colorScheme.surfaceContainerHighest,
          // 個人の工房カード（_WorkshopCardSlot）と同じ構成: 背景画像レイヤー
          // （タップで変更）→ 暗転グラデーション（装飾のみ、IgnorePointerで
          // ヒットテスト対象から外す）→ アイコン・名前・一言のレイヤー。
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
              // 下端が詰まって見えないよう、他の3辺より下側の余白を広めに取る。
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  padding,
                  padding,
                  padding,
                  padding * 1.8,
                ),
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
                    const SizedBox(height: padding * 0.6),
                    GestureDetector(
                      onTap: () => _editField(
                        label: strings.groupProfileCardNameLabel,
                        currentValue: _card.name,
                        maxLength: kMaxGroupProfileCardNameLength,
                        onChanged: (value) {
                          if (value.isEmpty) return;
                          setState(() => _card = _card.copyWith(name: value));
                        },
                      ),
                      child: Text(
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
                    ),
                    GestureDetector(
                      onTap: () => _editField(
                        label: strings.groupProfileCardDescriptionLabel,
                        currentValue: _card.description,
                        maxLength: kMaxGroupProfileCardDescriptionLength,
                        onChanged: (value) {
                          setState(
                            () => _card = _card.copyWith(description: value),
                          );
                        },
                      ),
                      child: Text(
                        _card.description.isEmpty
                            ? strings.groupProfileCardDescriptionLabel
                            : _card.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: descriptionFontSize,
                          color: hasBackground
                              ? Colors.white70
                              : colorScheme.onSurfaceVariant,
                        ),
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
    );
  }
}
