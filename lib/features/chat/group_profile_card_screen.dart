import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/group.dart';
import '../../models/group_profile_card.dart';
import '../../models/profile_card.dart' show ImageFocal;
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/focal_circle_avatar.dart';
import '../../widgets/focal_image.dart';
import '../profile/focal_edit_overlay.dart';

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
  Timer? _errorBannerTimer;

  /// 画像の見せ方（中心・拡大率）を調整中の対象（'background' / 'icon'）。
  /// 個人の工房カードの位置調整（`_focalEditing`）と同じ流れ。
  String? _focalEditing;
  ImageFocal _focalDraft = ImageFocal.center;

  void _startFocalEdit(String field) {
    setState(() {
      _focalEditing = field;
      _focalDraft =
          (field == 'background' ? _card.backgroundFocal : _card.iconFocal) ??
          ImageFocal.center;
    });
  }

  void _finishFocalEdit({required bool apply}) {
    final field = _focalEditing;
    setState(() => _focalEditing = null);
    if (!apply || field == null) return;
    final focal = _focalDraft.isDefault ? null : _focalDraft;
    setState(() {
      _card = field == 'background'
          ? _card.copyWith(
              backgroundFocal: focal,
              clearBackgroundFocal: focal == null,
            )
          : _card.copyWith(iconFocal: focal, clearIconFocal: focal == null);
    });
    _persist();
  }

  /// 位置調整中の画像を差し替える（差し替えると構図はやり直し）。
  Future<void> _replaceFocalImage() async {
    final field = _focalEditing;
    setState(() => _focalEditing = null);
    if (field == 'background') {
      await _pickBackground();
    } else if (field == 'icon') {
      await _pickIcon();
    }
  }

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
    _errorBannerTimer?.cancel();
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
          _errorBannerTimer = showAutoDismissBanner(
            context,
            message: '${ref.read(appStringsProvider).profileSaveError}: $e',
            previousTimer: _errorBannerTimer,
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
      _errorBannerTimer = showAutoDismissBanner(
        context,
        message: '${ref.read(appStringsProvider).profileIconUploadError}: $e',
        previousTimer: _errorBannerTimer,
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
      _errorBannerTimer = showAutoDismissBanner(
        context,
        message: '${ref.read(appStringsProvider).profileIconUploadError}: $e',
        previousTimer: _errorBannerTimer,
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
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    await showDialog<void>(
      context: context,
      builder: (context) {
        final title = Text(label);
        final content = TextField(
          controller: _editController,
          autofocus: true,
          maxLength: maxLength,
          onSubmitted: (_) => Navigator.of(context).pop(),
        );
        return isGlass
            ? GlassAlertDialog(title: title, content: content)
            : KeyboardAlertDialog(title: title, content: content);
      },
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

    final focalButtons = _focalEditing == null
        ? null
        : SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          side: const BorderSide(color: Colors.white70),
                        ),
                        onPressed: () => _finishFocalEdit(apply: false),
                        child: Text(
                          strings.workshopFocalCancel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          side: const BorderSide(color: Colors.white70),
                        ),
                        onPressed: () =>
                            setState(() => _focalDraft = ImageFocal.center),
                        child: Text(
                          strings.workshopFocalReset,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        onPressed: () => _finishFocalEdit(apply: true),
                        child: Text(
                          strings.workshopFocalDone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: _replaceFocalImage,
                  child: Text(strings.groupProfileCardChangeImage),
                ),
              ],
            ),
          );
    final card = SizedBox(
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
              // 画像があればタップで位置調整、無ければ画像を選ぶ。
              onTap: _uploadingBackground || _focalEditing != null
                  ? null
                  : background != null
                  ? () => _startFocalEdit('background')
                  : _pickBackground,
              child: background != null
                  ? FocalImage(url: background, focal: _card.backgroundFocal)
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
                    onTap: _uploadingIcon || _focalEditing != null
                        ? null
                        : _card.iconUrl != null
                        ? () => _startFocalEdit('icon')
                        : _pickIcon,
                    child: FocalCircleAvatar(
                      radius: avatarRadius,
                      url: _card.iconUrl,
                      focal: _card.iconFocal,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant,
                      fallback: _uploadingIcon
                          ? const SizedBox.shrink()
                          : const Icon(Icons.groups_outlined),
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
            if (_focalEditing != null)
              FocalEditOverlay(
                imageUrl: _focalEditing == 'background'
                    ? _card.backgroundImageUrl!
                    : _card.iconUrl!,
                circle: _focalEditing == 'icon',
                focal: _focalDraft,
                onChanged: (focal) => setState(() => _focalDraft = focal),
              ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          card,
          if (focalButtons != null) ...[
            const SizedBox(height: 12),
            focalButtons,
          ],
        ],
      ),
    );
  }
}
