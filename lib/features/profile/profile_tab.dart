import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_user.dart';
import '../../models/profile_card.dart';
import '../../models/profile_material.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/user_repository.dart';

enum _ProfileSubTab { kura, koubou }

/// ニックネーム・ステメ・プロフィールカードのローカル採番id。
/// 以前は`Random().nextInt(1 << 32)`だったが、`1 << 32`はDart VM（ウィジェット
/// テストの実行環境）では4294967296になる一方、Web（dart2js/DDC）では
/// JSのビット演算が32bit符号あり整数に切り詰められるため0になり、
/// `Random().nextInt(0)`が即座にRangeErrorを投げてsetStateの手前で
/// 処理が止まっていた（「ダイアログは閉じるが何も起こらない」の実体）。
/// 画像素材はFirestoreの`doc().id`でidを採番しておりこの経路を通らないため、
/// 影響は文字系の項目（ニックネーム・ステメ・工房カード）だけに出ていた。
/// ビット演算を経由しない10進リテラルにすることでVM・Web両方で正しく動く。
String _newLocalId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(4294967296)}';

/// 身だしなみタブ。「蔵」（素材の登録・管理）と「工房」（蔵の素材を組み合わせた
/// プロフィールカードの作成）をボタンで切り替えて表示する。
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
  _ProfileSubTab _subTab = _ProfileSubTab.kura;

  @override
  void initState() {
    super.initState();
    _user = widget.currentUser;
  }

  UserRepository get _repository => ref.read(userRepositoryProvider);

  // 蔵の各セクション（アイコン・背景画像・ステメ・ニックネーム）は、追加操作が
  // それぞれ独立して非同期に走る（特にアップロード系はStorage往復で数秒かかる）。
  // 以前はローカルで組み立てたAppUser全体を`.set()`で丸ごと上書きしていたため、
  // 「アイコンのアップロード中にニックネームを追加する」のように複数の操作が
  // 重なると、後から完了した書き込みが先に完了した書き込みを消してしまう
  // 競合（lost update）が起きていた（activeIconIdが存在しないicon idを指す、
  // 追加したはずのニックネームがFirestore上には一切残っていない、といった形で
  // 実際に確認された）。[_addToList]/[_removeFromList]/[_setField]は
  // Firestoreの`arrayUnion`/`arrayRemove`とフィールド単位の`update()`を使い、
  // サーバー側で原子的にマージされるようにすることでこの競合を解消する。

  Future<void> _addToList(String field, Map<String, dynamic> value) async {
    try {
      await _repository.addToProfileList(_user.userId, field, value);
    } catch (e) {
      _showError('${ref.read(appStringsProvider).profileSaveError}: $e');
    }
  }

  Future<void> _removeFromList(String field, Map<String, dynamic> value) async {
    try {
      await _repository.removeFromProfileList(_user.userId, field, value);
    } catch (e) {
      _showError('${ref.read(appStringsProvider).profileSaveError}: $e');
    }
  }

  Future<void> _setField(String field, String? value) async {
    try {
      await _repository.setProfileField(_user.userId, field, value);
    } catch (e) {
      _showError('${ref.read(appStringsProvider).profileSaveError}: $e');
    }
  }

  /// 「使うものを選ぶ」ラジオボタン操作（activeIconId等）。ローカルの表示は
  /// 即座に切り替え、Firestoreへはフィールド単位で反映する。
  Future<void> _selectField(String field, String id) async {
    setState(() {
      _user = switch (field) {
        'activeIconId' => _user.copyWith(activeIconId: id),
        'activeBackgroundImageId' => _user.copyWith(activeBackgroundImageId: id),
        'activeNicknameId' => _user.copyWith(activeNicknameId: id),
        'activeStatusMessageId' => _user.copyWith(activeStatusMessageId: id),
        _ => _user,
      };
    });
    await _setField(field, id);
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
      final shouldActivate = _user.activeIconId == null;
      setState(() {
        _user = _user.copyWith(
          icons: [..._user.icons, material],
          activeIconId: _user.activeIconId ?? material.id,
        );
      });
      await _addToList('icons', material.toJson());
      if (shouldActivate) await _setField('activeIconId', material.id);
    } catch (e) {
      _showError('${ref.read(appStringsProvider).profileIconUploadError}: $e');
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
      final shouldActivate = _user.activeBackgroundImageId == null;
      setState(() {
        _user = _user.copyWith(
          backgroundImages: [..._user.backgroundImages, material],
          activeBackgroundImageId: _user.activeBackgroundImageId ?? material.id,
        );
      });
      await _addToList('backgroundImages', material.toJson());
      if (shouldActivate) {
        await _setField('activeBackgroundImageId', material.id);
      }
    } catch (e) {
      _showError(
        '${ref.read(appStringsProvider).profileBackgroundUploadError}: $e',
      );
    } finally {
      if (mounted) setState(() => _uploadingBackground = false);
    }
  }

  Future<void> _deleteIcon(ProfileMaterial material) async {
    final remaining = _user.icons.where((m) => m.id != material.id).toList();
    final wasActive = _user.activeIconId == material.id;
    final nextActiveId = wasActive
        ? (remaining.isEmpty ? null : remaining.first.id)
        : _user.activeIconId;
    setState(() {
      _user = _user.copyWith(icons: remaining, activeIconId: nextActiveId);
    });
    await _removeFromList('icons', material.toJson());
    if (wasActive) await _setField('activeIconId', nextActiveId);
    try {
      await _repository.deleteProfileMaterial(material);
    } catch (e) {
      _showError('${ref.read(appStringsProvider).profileIconUploadError}: $e');
    }
  }

  Future<void> _deleteBackground(ProfileMaterial material) async {
    final remaining =
        _user.backgroundImages.where((m) => m.id != material.id).toList();
    final wasActive = _user.activeBackgroundImageId == material.id;
    final nextActiveId = wasActive
        ? (remaining.isEmpty ? null : remaining.first.id)
        : _user.activeBackgroundImageId;
    setState(() {
      _user = _user.copyWith(
        backgroundImages: remaining,
        activeBackgroundImageId: nextActiveId,
      );
    });
    await _removeFromList('backgroundImages', material.toJson());
    if (wasActive) await _setField('activeBackgroundImageId', nextActiveId);
    try {
      await _repository.deleteProfileMaterial(material);
    } catch (e) {
      _showError(
        '${ref.read(appStringsProvider).profileBackgroundUploadError}: $e',
      );
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
      id: _newLocalId(),
      text: text.trim(),
    );
    final shouldActivate = _user.activeStatusMessageId == null;
    setState(() {
      _user = _user.copyWith(
        statusMessages: [..._user.statusMessages, message],
        activeStatusMessageId: _user.activeStatusMessageId ?? message.id,
      );
    });
    await _addToList('statusMessages', message.toJson());
    if (shouldActivate) await _setField('activeStatusMessageId', message.id);
  }

  Future<void> _editStatusMessage(StatusMessage message) async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => _StatusMessageDialog(initialText: message.text),
    );
    if (text == null || text.trim().isEmpty || text.trim() == message.text) {
      return;
    }

    // id自体は変えず本文だけ差し替える。activeStatusMessageIdは
    // idで参照しているため、id維持であれば選択状態は自動的に保たれる。
    final updated = StatusMessage(id: message.id, text: text.trim());
    setState(() {
      _user = _user.copyWith(
        statusMessages: [
          for (final m in _user.statusMessages)
            if (m.id == message.id) updated else m,
        ],
      );
    });
    await _removeFromList('statusMessages', message.toJson());
    await _addToList('statusMessages', updated.toJson());
  }

  Future<void> _deleteStatusMessage(StatusMessage message) async {
    final remaining =
        _user.statusMessages.where((m) => m.id != message.id).toList();
    final wasActive = _user.activeStatusMessageId == message.id;
    final nextActiveId = wasActive
        ? (remaining.isEmpty ? null : remaining.first.id)
        : _user.activeStatusMessageId;
    setState(() {
      _user = _user.copyWith(
        statusMessages: remaining,
        activeStatusMessageId: nextActiveId,
      );
    });
    await _removeFromList('statusMessages', message.toJson());
    if (wasActive) await _setField('activeStatusMessageId', nextActiveId);
  }

  Future<void> _addNickname() async {
    if (_user.nicknames.length >= kMaxNicknames) return;
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _NicknameDialog(),
    );
    if (text == null || text.trim().isEmpty) return;

    final nickname = Nickname(
      id: _newLocalId(),
      text: text.trim(),
    );
    final shouldActivate = _user.activeNicknameId == null;
    setState(() {
      _user = _user.copyWith(
        nicknames: [..._user.nicknames, nickname],
        activeNicknameId: _user.activeNicknameId ?? nickname.id,
      );
    });
    await _addToList('nicknames', nickname.toJson());
    if (shouldActivate) await _setField('activeNicknameId', nickname.id);
  }

  Future<void> _editNickname(Nickname nickname) async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => _NicknameDialog(initialText: nickname.text),
    );
    if (text == null || text.trim().isEmpty || text.trim() == nickname.text) {
      return;
    }

    final updated = Nickname(id: nickname.id, text: text.trim());
    setState(() {
      _user = _user.copyWith(
        nicknames: [
          for (final n in _user.nicknames)
            if (n.id == nickname.id) updated else n,
        ],
      );
    });
    await _removeFromList('nicknames', nickname.toJson());
    await _addToList('nicknames', updated.toJson());
  }

  Future<void> _deleteNickname(Nickname nickname) async {
    final remaining =
        _user.nicknames.where((n) => n.id != nickname.id).toList();
    final wasActive = _user.activeNicknameId == nickname.id;
    final nextActiveId = wasActive
        ? (remaining.isEmpty ? null : remaining.first.id)
        : _user.activeNicknameId;
    setState(() {
      _user = _user.copyWith(
        nicknames: remaining,
        activeNicknameId: nextActiveId,
      );
    });
    await _removeFromList('nicknames', nickname.toJson());
    if (wasActive) await _setField('activeNicknameId', nextActiveId);
  }

  Future<void> _saveCard(ProfileCard card, {required bool isNew}) async {
    if (isNew) {
      setState(() {
        _user = _user.copyWith(profileCards: [..._user.profileCards, card]);
      });
      await _addToList('profileCards', card.toJson());
    } else {
      final previous = _user.profileCards.firstWhere((c) => c.id == card.id);
      setState(() {
        _user = _user.copyWith(
          profileCards: [
            for (final c in _user.profileCards)
              if (c.id == card.id) card else c,
          ],
        );
      });
      // ProfileCardは配列内の値そのもので一致判定するarrayUnion/arrayRemoveの
      // 対象になるため、編集は「古い値を削除」→「新しい値を追加」の2手順で行う。
      await _removeFromList('profileCards', previous.toJson());
      await _addToList('profileCards', card.toJson());
    }
  }

  Future<void> _deleteCard(ProfileCard card) async {
    setState(() {
      _user = _user.copyWith(
        profileCards: _user.profileCards.where((c) => c.id != card.id).toList(),
      );
    });
    await _removeFromList('profileCards', card.toJson());
  }

  /// カードをタップした位置からズームインさせる形でカード編集画面を開く。
  /// Heroタグはカードの中身ではなく枠の位置（[index]）に紐づけている。
  /// 空き枠→作成後は同じ枠が実カードに置き換わるだけで、開いている最中の
  /// このルート自体は同一タグのHeroを使い続けるため問題ない。
  Future<void> _openCardZoom(int index, ProfileCard? existing) async {
    final strings = ref.read(appStringsProvider);
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (_, animation, secondaryAnimation) => Center(
          child: _CardZoomEditor(
            heroTag: 'profile-card-slot-$index',
            user: _user,
            strings: strings,
            initialCard: existing,
            onCreate: (card) => _saveCard(card, isNew: true),
            onUpdate: (card) => _saveCard(card, isNew: false),
            onDelete: _deleteCard,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SegmentedButton<_ProfileSubTab>(
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            segments: [
              ButtonSegment(
                value: _ProfileSubTab.kura,
                icon: const Icon(Icons.inventory_2_outlined),
                // 以前はFittedBox(scaleDown)で「入り切らなければ縮小」させて
                // いたが、これだと用語スタイル（世界観重視/利便性重視）や
                // 画面幅・OSのテキストスケール設定の組み合わせ次第でラベルの
                // 実際のフォントサイズがまちまちになってしまっていた。
                // 環境によって文字サイズを可変にするのではなく、設定タブの
                // 列幅（`_kSettingsColumnWidth`）と同じ考え方で、枠の方を
                // 最長ラベル（利便性重視の「マテリアルボックス」やEnglishの
                // 「Assembly Studio」等）が収まる固定幅にし、文字サイズは
                // 常に一定にする。短い語（「蔵」等）のときは中央寄せの余白が
                // 増えるだけになる。
                label: _WorkshopToggleLabel(text: vocab.profileStorage),
              ),
              ButtonSegment(
                value: _ProfileSubTab.koubou,
                icon: const Icon(Icons.gavel),
                label: _WorkshopToggleLabel(text: vocab.profileCreator),
              ),
            ],
            selected: {_subTab},
            onSelectionChanged: (selection) =>
                setState(() => _subTab = selection.first),
          ),
        ),
        Expanded(
          child: _subTab == _ProfileSubTab.kura
              ? _KuraView(
                  user: _user,
                  strings: strings,
                  uploadingIcon: _uploadingIcon,
                  uploadingBackground: _uploadingBackground,
                  onAddIcon: _pickAndUploadIcon,
                  onSelectIcon: (id) => _selectField('activeIconId', id),
                  onDeleteIcon: _deleteIcon,
                  onAddBackground: _pickAndUploadBackground,
                  onSelectBackground: (id) =>
                      _selectField('activeBackgroundImageId', id),
                  onDeleteBackground: _deleteBackground,
                  onAddNickname: _addNickname,
                  onSelectNickname: (id) => _selectField('activeNicknameId', id),
                  onEditNickname: _editNickname,
                  onDeleteNickname: _deleteNickname,
                  onAddStatusMessage: _addStatusMessage,
                  onSelectStatusMessage: (id) =>
                      _selectField('activeStatusMessageId', id),
                  onEditStatusMessage: _editStatusMessage,
                  onDeleteStatusMessage: _deleteStatusMessage,
                )
              : _WorkshopView(
                  user: _user,
                  strings: strings,
                  vocab: vocab,
                  onTapSlot: _openCardZoom,
                ),
        ),
      ],
    );
  }
}

/// 「蔵/工房」切り替えボタンのラベル。用語スタイル・言語が変わってもフォント
/// サイズが縮小されないよう、最長ラベルが収まる固定幅で中央寄せ表示する
/// （短いラベルのときは余白が増えるだけになる）。
class _WorkshopToggleLabel extends StatelessWidget {
  const _WorkshopToggleLabel({required this.text});

  final String text;

  // 最長ラベル（利便性重視JAの「マテリアルボックス」9字）がフォントサイズ12で
  // 折り返し・省略なしに収まる幅。短いラベルはこの幅の中で中央寄せになる。
  // 100pxでは「マテリアルボックス」が省略されてしまったため、余裕を持たせて
  // 140pxに広げている。
  static const _width = 140.0;
  static const _fontSize = 12.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: _fontSize),
      ),
    );
  }
}

/// 蔵タブ: プレビュー＋アイコン・背景画像・ニックネーム・ステメの登録セクション。
class _KuraView extends StatelessWidget {
  const _KuraView({
    required this.user,
    required this.strings,
    required this.uploadingIcon,
    required this.uploadingBackground,
    required this.onAddIcon,
    required this.onSelectIcon,
    required this.onDeleteIcon,
    required this.onAddBackground,
    required this.onSelectBackground,
    required this.onDeleteBackground,
    required this.onAddNickname,
    required this.onSelectNickname,
    required this.onEditNickname,
    required this.onDeleteNickname,
    required this.onAddStatusMessage,
    required this.onSelectStatusMessage,
    required this.onEditStatusMessage,
    required this.onDeleteStatusMessage,
  });

  final AppUser user;
  final Strings strings;
  final bool uploadingIcon;
  final bool uploadingBackground;
  final VoidCallback onAddIcon;
  final ValueChanged<String> onSelectIcon;
  final ValueChanged<ProfileMaterial> onDeleteIcon;
  final VoidCallback onAddBackground;
  final ValueChanged<String> onSelectBackground;
  final ValueChanged<ProfileMaterial> onDeleteBackground;
  final VoidCallback onAddNickname;
  final ValueChanged<String> onSelectNickname;
  final ValueChanged<Nickname> onEditNickname;
  final ValueChanged<Nickname> onDeleteNickname;
  final VoidCallback onAddStatusMessage;
  final ValueChanged<String> onSelectStatusMessage;
  final ValueChanged<StatusMessage> onEditStatusMessage;
  final ValueChanged<StatusMessage> onDeleteStatusMessage;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MaterialSection(
          title: strings.profileIconSection,
          count: user.icons.length,
          max: kMaxIcons,
          uploading: uploadingIcon,
          onAdd: onAddIcon,
          children: [
            for (final icon in user.icons)
              _CircleMaterialThumb(
                url: icon.url,
                selected: icon.id == user.activeIconId,
                onTap: () => onSelectIcon(icon.id),
                onDelete: () => onDeleteIcon(icon),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _MaterialSection(
          title: strings.profileBackgroundSection,
          count: user.backgroundImages.length,
          max: kMaxBackgroundImages,
          uploading: uploadingBackground,
          onAdd: onAddBackground,
          children: [
            for (final bg in user.backgroundImages)
              _RectMaterialThumb(
                url: bg.url,
                selected: bg.id == user.activeBackgroundImageId,
                onTap: () => onSelectBackground(bg.id),
                onDelete: () => onDeleteBackground(bg),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _NicknameSection(
          strings: strings,
          nicknames: user.nicknames,
          activeId: user.activeNicknameId,
          onAdd: onAddNickname,
          onSelect: onSelectNickname,
          onEdit: onEditNickname,
          onDelete: onDeleteNickname,
        ),
        const SizedBox(height: 24),
        _StatusMessageSection(
          strings: strings,
          messages: user.statusMessages,
          activeId: user.activeStatusMessageId,
          onAdd: onAddStatusMessage,
          onSelect: onSelectStatusMessage,
          onEdit: onEditStatusMessage,
          onDelete: onDeleteStatusMessage,
        ),
      ],
    );
  }
}

/// 工房タブ: 蔵の素材を組み合わせた最大[kMaxProfileCards]枚のプロフィールカード。
/// 常に[kMaxProfileCards]枠を表示し、未作成の枠は「+」付きの白紙カードとして
/// 表示する。どの枠をタップしても選択画面（[_ProfileCardEditorDialog]）が開く。
class _WorkshopView extends StatelessWidget {
  const _WorkshopView({
    required this.user,
    required this.strings,
    required this.vocab,
    required this.onTapSlot,
  });

  final AppUser user;
  final Strings strings;
  final Vocabulary vocab;

  /// 枠番号（Heroタグ用）とその枠の現在のカード（未作成ならnull）を渡す。
  final void Function(int index, ProfileCard? card) onTapSlot;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          strings.workshopDescriptionTemplate(vocab.profileStorage),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        // 以前は固定サイズ（160x200）のカードを画面左端に詰めて表示していたため、
        // 広い画面では余白ばかりが目立っていた。3枠固定という前提を活かし、
        // 画面幅いっぱいを3等分してカード自体を大きく表示する（上限は
        // 超ワイド画面でカードが際限なく巨大化しないための保険程度に留める）。
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 24.0;
            const minCardWidth = 160.0;
            const maxCardWidth = 640.0;
            final rawWidth =
                (constraints.maxWidth - gap * (kMaxProfileCards - 1)) /
                    kMaxProfileCards;
            final cardWidth = rawWidth.clamp(minCardWidth, maxCardWidth);
            final cardHeight = cardWidth * 1.25;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < kMaxProfileCards; i++)
                  if (i < user.profileCards.length)
                    _WorkshopCardSlot(
                      index: i,
                      card: user.profileCards[i],
                      user: user,
                      strings: strings,
                      width: cardWidth,
                      height: cardHeight,
                      onTap: () => onTapSlot(i, user.profileCards[i]),
                    )
                  else
                    _WorkshopBlankSlot(
                      index: i,
                      width: cardWidth,
                      height: cardHeight,
                      onTap: () => onTapSlot(i, null),
                    ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WorkshopBlankSlot extends StatelessWidget {
  const _WorkshopBlankSlot({
    required this.index,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final int index;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: Hero(
        tag: 'profile-card-slot-$index',
        child: Material(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant,
                  width: 1.5,
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.add,
                  size: (width * 0.2).clamp(32.0, 64.0),
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkshopCardSlot extends StatelessWidget {
  const _WorkshopCardSlot({
    required this.index,
    required this.card,
    required this.user,
    required this.strings,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final int index;
  final ProfileCard card;
  final AppUser user;
  final Strings strings;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = _findById(user.icons, card.iconId);
    final background = _findById(user.backgroundImages, card.backgroundImageId);
    final nickname = _findById(user.nicknames, card.nicknameId)?.text;
    final statusMessage =
        _findById(user.statusMessages, card.statusMessageId)?.text;

    // カードが大きくなったのにアイコン・文字が160px時代の固定サイズのままだと
    // 中身が寂しく見えるため、カード幅に応じて緩やかにスケールさせる。
    final avatarRadius = (width * 0.11).clamp(18.0, 44.0);
    final padding = (width * 0.075).clamp(12.0, 28.0);
    // カード内はニックネームを主役にし（旧・カード名と同じ見せ方）、
    // その下にステメを補足として表示する。カード名自体はカードの外
    // （下）に表示するため、カード内には出さない。
    final nicknameFontSize = (width * 0.09).clamp(14.0, 24.0);
    final statusFontSize = (width * 0.055).clamp(11.0, 16.0);
    final subtitleColor = background != null
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: width,
          height: height,
          // 削除ボタンはズームイン後の編集画面側にのみ置く（Heroの中に含めると
          // 始点/終点でウィジェットツリーが変わりアニメーションが不自然になるため）。
          child: Hero(
            tag: 'profile-card-slot-$index',
            child: Material(
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              // 背景画像・グラデーション・タップ可能な内容をそれぞれ独立した
              // レイヤーとして`Stack(fit: expand)`で重ねることで、内容側の
              // パディングやテキスト量に関係なく背景が常にカード全体
              // （角丸の内側いっぱい）を覆うようにする。
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (background != null)
                    Image.network(background.url, fit: BoxFit.cover),
                  if (background != null)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black54],
                        ),
                      ),
                    ),
                  InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: EdgeInsets.all(padding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          CircleAvatar(
                            radius: avatarRadius,
                            backgroundImage:
                                icon != null ? NetworkImage(icon.url) : null,
                            child:
                                icon == null ? const Icon(Icons.person) : null,
                          ),
                          SizedBox(height: padding * 0.6),
                          Text(
                            nickname ?? strings.workshopFieldNickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: nicknameFontSize,
                              fontWeight: FontWeight.bold,
                              color: background != null ? Colors.white : null,
                            ),
                          ),
                          Text(
                            statusMessage ?? strings.workshopFieldStatusMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: statusFontSize,
                              color: subtitleColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: width,
          child: Text(
            card.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

/// カード名・ニックネーム・ステメなど、`id`フィールドを持つ蔵の素材から
/// idで1件だけ検索する（[_WorkshopCardSlot]・[_CardZoomEditor]で共用）。
T? _findById<T>(List<T> items, String? id) {
  if (id == null) return null;
  for (final item in items) {
    final dynamic d = item;
    if (d.id == id) return item;
  }
  return null;
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

/// アップロード直後の画像がまだCDNに伝播していない、あるいは
/// ブラウザがデコードできない形式（HEICなど）だった場合に、
/// 何も表示されない「真っ白」な状態のまま気づけないことがあったため、
/// 読み込み中はスピナー、失敗時は壊れた画像アイコンを明示的に表示する。
class _NetworkThumbImage extends StatelessWidget {
  const _NetworkThumbImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? accent : Colors.transparent,
                width: 3,
              ),
            ),
            child: ClipOval(
              child: _NetworkThumbImage(url: url),
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
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? accent : Colors.transparent,
                width: 3,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: _NetworkThumbImage(url: url),
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
    required this.strings,
    required this.messages,
    required this.activeId,
    required this.onAdd,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final Strings strings;
  final List<StatusMessage> messages;
  final String? activeId;
  final VoidCallback onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<StatusMessage> onEdit;
  final ValueChanged<StatusMessage> onDelete;

  @override
  Widget build(BuildContext context) {
    final canAdd = messages.length < kMaxStatusMessages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${strings.profileStatusMessageSection}（${messages.length}/$kMaxStatusMessages）',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        for (final message in messages)
          RadioGroup<String>(
            groupValue: activeId ?? '',
            onChanged: (value) {
              if (value != null) onSelect(value);
            },
            child: _RegisteredItemRow(
              value: message.id,
              text: message.text,
              onEdit: () => onEdit(message),
              onDelete: () => onDelete(message),
            ),
          ),
        TextButton.icon(
          onPressed: canAdd ? onAdd : null,
          icon: const Icon(Icons.add),
          label: Text(strings.profileAddStatusMessage),
        ),
      ],
    );
  }
}

class _NicknameSection extends StatelessWidget {
  const _NicknameSection({
    required this.strings,
    required this.nicknames,
    required this.activeId,
    required this.onAdd,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final Strings strings;
  final List<Nickname> nicknames;
  final String? activeId;
  final VoidCallback onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<Nickname> onEdit;
  final ValueChanged<Nickname> onDelete;

  @override
  Widget build(BuildContext context) {
    final canAdd = nicknames.length < kMaxNicknames;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${strings.profileNicknameSection}（${nicknames.length}/$kMaxNicknames）',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          strings.profileNicknameHint,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        for (final nickname in nicknames)
          RadioGroup<String>(
            groupValue: activeId ?? '',
            onChanged: (value) {
              if (value != null) onSelect(value);
            },
            child: _RegisteredItemRow(
              value: nickname.id,
              text: nickname.text,
              onEdit: () => onEdit(nickname),
              onDelete: () => onDelete(nickname),
            ),
          ),
        TextButton.icon(
          onPressed: canAdd ? onAdd : null,
          icon: const Icon(Icons.add),
          label: Text(strings.profileAddNickname),
        ),
      ],
    );
  }
}

/// ニックネーム・ステメの1行（選択用ラジオ＋テキスト＋編集／削除ボタン）。
/// 以前は`ListTile`を使っていたため、リスト全体の横幅いっぱいに引き伸ばされ、
/// 削除ボタンがテキストから大きく離れた画面右端に表示されてしまっていた。
/// `mainAxisSize: MainAxisSize.min`のRowにすることで、テキストのすぐ右に
/// ボタンが並ぶコンパクトな見た目にする。
class _RegisteredItemRow extends StatelessWidget {
  const _RegisteredItemRow({
    required this.value,
    required this.text,
    required this.onEdit,
    required this.onDelete,
  });

  final String value;
  final String text;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(value: value),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: onEdit,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: onDelete,
        ),
      ],
    );
  }
}

class _NicknameDialog extends ConsumerStatefulWidget {
  const _NicknameDialog({this.initialText});

  /// 編集時は既存のテキストを渡す。nullなら新規追加。
  final String? initialText;

  @override
  ConsumerState<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends ConsumerState<_NicknameDialog> {
  late final _controller = TextEditingController(text: widget.initialText);
  String? _errorText;

  bool get _isEdit => widget.initialText != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 未入力のまま追加ボタンを押しても、以前は何も起きたように見えなかった
  // （呼び出し元が空文字を無言でreturnしていたため）。押した結果が必ず
  // 見えるよう、ここでエラー表示してから閉じないようにする。
  void _submit() {
    if (_controller.text.trim().isEmpty) {
      setState(() => _errorText = ref.read(appStringsProvider).fieldRequiredError);
      return;
    }
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    return AlertDialog(
      title: Text(
        _isEdit
            ? strings.profileNicknameDialogEditTitle
            : strings.profileNicknameDialogTitle,
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: kMaxNicknameLength,
        decoration: InputDecoration(
          hintText: strings.profileNicknameDialogHint,
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(_isEdit ? strings.save : strings.add),
        ),
      ],
    );
  }
}

class _StatusMessageDialog extends ConsumerStatefulWidget {
  const _StatusMessageDialog({this.initialText});

  /// 編集時は既存のテキストを渡す。nullなら新規追加。
  final String? initialText;

  @override
  ConsumerState<_StatusMessageDialog> createState() =>
      _StatusMessageDialogState();
}

class _StatusMessageDialogState extends ConsumerState<_StatusMessageDialog> {
  late final _controller = TextEditingController(text: widget.initialText);
  String? _errorText;

  bool get _isEdit => widget.initialText != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isEmpty) {
      setState(() => _errorText = ref.read(appStringsProvider).fieldRequiredError);
      return;
    }
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    return AlertDialog(
      title: Text(
        _isEdit
            ? strings.profileStatusMessageDialogEditTitle
            : strings.profileStatusMessageDialogTitle,
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: kMaxStatusMessageLength,
        decoration: InputDecoration(
          hintText: strings.profileStatusMessageDialogHint,
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(_isEdit ? strings.save : strings.add),
        ),
      ],
    );
  }
}

/// 工房: プロフィールカードの編集画面。カードそのものをズームインした形で表示し、
/// カード上の各素材（背景画像・アイコン・ニックネーム・ステメ）を直接タップすると、
/// その種類だけの登録済み素材一覧がポップアップし、選ぶとその場で即時保存される。
/// カード名だけは自由入力のためポップの対象外（編集アイコンから編集する）。
class _CardZoomEditor extends StatefulWidget {
  const _CardZoomEditor({
    required this.heroTag,
    required this.user,
    required this.strings,
    required this.initialCard,
    required this.onCreate,
    required this.onUpdate,
    required this.onDelete,
  });

  final String heroTag;
  final AppUser user;
  final Strings strings;

  /// nullなら空き枠（まだFirestoreに存在しないカード）。
  final ProfileCard? initialCard;

  /// 新規カードの名前が初めて確定した時点で1回だけ呼ばれる。
  final Future<void> Function(ProfileCard card) onCreate;

  /// 既存カードのフィールドを1つ変更するたびに呼ばれる。
  final Future<void> Function(ProfileCard card) onUpdate;
  final Future<void> Function(ProfileCard card) onDelete;

  @override
  State<_CardZoomEditor> createState() => _CardZoomEditorState();
}

class _CardZoomEditorState extends State<_CardZoomEditor> {
  ProfileCard? _card;
  late final TextEditingController _nameController;
  bool _editingName = false;
  Offset? _lastTapPosition;

  @override
  void initState() {
    super.initState();
    _card = widget.initialCard;
    _nameController = TextEditingController(text: widget.initialCard?.name);
    _editingName = widget.initialCard == null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _confirmName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final card = _card;
    if (card == null) {
      final created = ProfileCard(id: _newLocalId(), name: name);
      setState(() {
        _card = created;
        _editingName = false;
      });
      await widget.onCreate(created);
      return;
    }
    if (name == card.name) {
      setState(() => _editingName = false);
      return;
    }
    final updated = card.copyWith(name: name);
    setState(() {
      _card = updated;
      _editingName = false;
    });
    await widget.onUpdate(updated);
  }

  Future<void> _pickMaterial(String field) async {
    final card = _card;
    if (card == null) return;

    final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox;
    final tapPosition = _lastTapPosition ?? overlayBox.size.center(Offset.zero);
    final position = RelativeRect.fromRect(
      Rect.fromPoints(tapPosition, tapPosition),
      Offset.zero & overlayBox.size,
    );
    final strings = widget.strings;

    String? result;
    switch (field) {
      case 'icon':
        result = await _showImageMaterialMenu(
          context,
          position,
          widget.user.icons,
          card.iconId,
          strings,
        );
      case 'background':
        result = await _showImageMaterialMenu(
          context,
          position,
          widget.user.backgroundImages,
          card.backgroundImageId,
          strings,
        );
      case 'nickname':
        result = await _showTextMaterialMenu(
          context,
          position,
          [for (final n in widget.user.nicknames) (n.id, n.text)],
          card.nicknameId,
          strings,
        );
      case 'statusMessage':
        result = await _showTextMaterialMenu(
          context,
          position,
          [for (final m in widget.user.statusMessages) (m.id, m.text)],
          card.statusMessageId,
          strings,
        );
    }
    if (result == null || !mounted) return;

    final id = result.isEmpty ? null : result;
    final updated = switch (field) {
      'icon' => card.copyWith(iconId: id, clearIconId: id == null),
      'background' =>
        card.copyWith(backgroundImageId: id, clearBackgroundImageId: id == null),
      'nickname' => card.copyWith(nicknameId: id, clearNicknameId: id == null),
      _ => card.copyWith(statusMessageId: id, clearStatusMessageId: id == null),
    };
    setState(() => _card = updated);
    await widget.onUpdate(updated);
  }

  Future<void> _handleDelete() async {
    final card = _card;
    if (card == null) return;
    await widget.onDelete(card);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * 0.8).clamp(240.0, 420.0);
    final height = width * 1.25;
    final strings = widget.strings;
    final card = _card;
    final colorScheme = Theme.of(context).colorScheme;

    final icon = card == null ? null : _findById(widget.user.icons, card.iconId);
    final background =
        card == null ? null : _findById(widget.user.backgroundImages, card.backgroundImageId);
    final nickname = card == null ? null : _findById(widget.user.nicknames, card.nicknameId);
    final statusMessage =
        card == null ? null : _findById(widget.user.statusMessages, card.statusMessageId);
    // ニックネーム・ステメはカード内（背景画像や暗いオーバーレイの上）に
    // 表示するため、背景の有無で見やすい色を切り替える。カード名はカードの
    // 外（下、暗転した背景の上）に表示するため常に白系の固定色にする。
    final nicknameColor = background != null ? Colors.white : null;
    final statusColor = background != null ? Colors.white70 : colorScheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Hero(
              tag: widget.heroTag,
              child: Material(
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.circular(24),
                color: colorScheme.surfaceContainerHighest,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        onTapDown: (details) =>
                            _lastTapPosition = details.globalPosition,
                        onTap: card == null ? null : () => _pickMaterial('background'),
                        child: background != null
                            ? Image.network(background.url, fit: BoxFit.cover)
                            : ColoredBox(color: colorScheme.surfaceContainerHighest),
                      ),
                      if (background != null)
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black54],
                            ),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.all(width * 0.08),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTapDown: (details) =>
                                  _lastTapPosition = details.globalPosition,
                              onTap: card == null ? null : () => _pickMaterial('icon'),
                              child: Opacity(
                                opacity: card == null ? 0.4 : 1,
                                child: CircleAvatar(
                                  radius: width * 0.13,
                                  backgroundImage:
                                      icon != null ? NetworkImage(icon.url) : null,
                                  child:
                                      icon == null ? const Icon(Icons.person) : null,
                                ),
                              ),
                            ),
                            if (card != null) ...[
                              SizedBox(height: width * 0.05),
                              // カード内はニックネームを主役として表示し、
                              // その下にステメを補足として表示する。
                              GestureDetector(
                                onTapDown: (details) =>
                                    _lastTapPosition = details.globalPosition,
                                onTap: () => _pickMaterial('nickname'),
                                child: Text(
                                  nickname?.text ?? strings.workshopFieldNickname,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: width * 0.075,
                                    fontWeight: FontWeight.bold,
                                    color: nicknameColor,
                                  ),
                                ),
                              ),
                              SizedBox(height: width * 0.02),
                              GestureDetector(
                                onTapDown: (details) =>
                                    _lastTapPosition = details.globalPosition,
                                onTap: () => _pickMaterial('statusMessage'),
                                child: Text(
                                  statusMessage?.text ??
                                      strings.workshopFieldStatusMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: width * 0.045,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -12,
              top: -12,
              child: _RoundIconButton(
                icon: Icons.close,
                tooltip: strings.workshopCloseTooltip,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            if (card != null)
              Positioned(
                left: -12,
                top: -12,
                child: _RoundIconButton(
                  icon: Icons.delete_outline,
                  tooltip: strings.workshopDeleteCardTooltip,
                  onTap: _handleDelete,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // カード名はカードの外（下）に表示する。暗転した背景の上に乗るため
        // 固定で白系の色にする。
        SizedBox(
          width: width,
          child: _editingName
              ? TextField(
                  controller: _nameController,
                  autofocus: true,
                  maxLength: kMaxWorkshopCardNameLength,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: strings.workshopCardNameLabel,
                    hintStyle: const TextStyle(color: Colors.white70),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white70),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                  onSubmitted: (_) => _confirmName(),
                  onTapOutside: (_) => _confirmName(),
                )
              : GestureDetector(
                  onTap: () => setState(() => _editingName = true),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          card!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 16, color: Colors.white70),
                    ],
                  ),
                ),
        ),
        if (card == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              strings.workshopNameRequiredHint,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
      ],
    );
  }
}

/// ズームイン編集画面右上の閉じるボタン・左上の削除ボタンに使う丸ボタン。
/// Hero対象の外側に置くため、[_CardZoomEditor]の独自ウィジェットとして分離している。
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// アイコン・背景画像用のポップアップ（同じ種類の素材だけを一覧表示する）。
/// 戻り値は素材id、空文字列は「なし」の選択、nullはポップを閉じただけ（変更なし）。
Future<String?> _showImageMaterialMenu(
  BuildContext context,
  RelativeRect position,
  List<ProfileMaterial> materials,
  String? selectedId,
  Strings strings,
) {
  return showMenu<String>(
    context: context,
    position: position,
    items: [
      PopupMenuItem<String>(
        value: '',
        child: _MaterialMenuRow(selected: selectedId == null, label: strings.workshopChoiceNone),
      ),
      if (materials.isEmpty)
        PopupMenuItem<String>(
          enabled: false,
          child: Text(strings.workshopEmptyMaterialHint),
        ),
      for (final material in materials)
        PopupMenuItem<String>(
          value: material.id,
          child: _MaterialMenuRow(
            selected: selectedId == material.id,
            label: '',
            thumbnail: _NetworkThumbImage(url: material.url),
          ),
        ),
    ],
  );
}

/// ニックネーム・ステメ用のポップアップ（同じ種類の素材だけを一覧表示する）。
/// 戻り値の意味は[_showImageMaterialMenu]と同じ。
Future<String?> _showTextMaterialMenu(
  BuildContext context,
  RelativeRect position,
  List<(String, String)> items,
  String? selectedId,
  Strings strings,
) {
  return showMenu<String>(
    context: context,
    position: position,
    items: [
      PopupMenuItem<String>(
        value: '',
        child: _MaterialMenuRow(selected: selectedId == null, label: strings.workshopChoiceNone),
      ),
      if (items.isEmpty)
        PopupMenuItem<String>(
          enabled: false,
          child: Text(strings.workshopEmptyMaterialHint),
        ),
      for (final (id, text) in items)
        PopupMenuItem<String>(
          value: id,
          child: _MaterialMenuRow(selected: selectedId == id, label: text),
        ),
    ],
  );
}

class _MaterialMenuRow extends StatelessWidget {
  const _MaterialMenuRow({
    required this.selected,
    required this.label,
    this.thumbnail,
  });

  final bool selected;
  final String label;
  final Widget? thumbnail;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          child: selected ? const Icon(Icons.check, size: 18) : null,
        ),
        if (thumbnail != null) ...[
          SizedBox(width: 28, height: 28, child: ClipOval(child: thumbnail)),
          const SizedBox(width: 8),
        ],
        if (label.isNotEmpty) Text(label),
      ],
    );
  }
}
