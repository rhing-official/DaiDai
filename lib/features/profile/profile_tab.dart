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

  Future<void> _openCardEditor(ProfileCard? existing) async {
    final card = await showDialog<ProfileCard>(
      context: context,
      builder: (_) => _ProfileCardEditorDialog(user: _user, existing: existing),
    );
    if (card == null) return;
    await _saveCard(card, isNew: existing == null);
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            segments: [
              ButtonSegment(
                value: _ProfileSubTab.kura,
                icon: const Icon(Icons.inventory_2_outlined),
                // softWrap: falseだけでは「入り切らない分がクリップされて
                // 見えなくなる」だけで、幅が足りない状況自体は解決しない
                // （paddingで余裕を持たせても、画面幅や用語スタイルの組み
                // 合わせ次第で再び足りなくなり得る）。FittedBoxで包み、
                // 入り切らないときは文字を縮小して必ず全体を表示させる。
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(vocab.profileStorage, softWrap: false),
                ),
              ),
              ButtonSegment(
                value: _ProfileSubTab.koubou,
                icon: const Icon(Icons.gavel),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(vocab.profileCreator, softWrap: false),
                ),
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
                  onTapSlot: _openCardEditor,
                  onDeleteCard: _deleteCard,
                ),
        ),
      ],
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
    required this.onDeleteCard,
  });

  final AppUser user;
  final Strings strings;
  final Vocabulary vocab;
  final ValueChanged<ProfileCard?> onTapSlot;
  final ValueChanged<ProfileCard> onDeleteCard;

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
                      card: user.profileCards[i],
                      user: user,
                      strings: strings,
                      width: cardWidth,
                      height: cardHeight,
                      onTap: () => onTapSlot(user.profileCards[i]),
                      onDelete: () => onDeleteCard(user.profileCards[i]),
                    )
                  else
                    _WorkshopBlankSlot(
                      width: cardWidth,
                      height: cardHeight,
                      onTap: () => onTapSlot(null),
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
    required this.width,
    required this.height,
    required this.onTap,
  });

  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
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
    );
  }
}

class _WorkshopCardSlot extends StatelessWidget {
  const _WorkshopCardSlot({
    required this.card,
    required this.user,
    required this.strings,
    required this.width,
    required this.height,
    required this.onTap,
    required this.onDelete,
  });

  final ProfileCard card;
  final AppUser user;
  final Strings strings;
  final double width;
  final double height;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final icon = _findById(user.icons, card.iconId);
    final background = _findById(user.backgroundImages, card.backgroundImageId);
    final nickname = _findById(user.nicknames, card.nicknameId)?.text;
    final statusMessage =
        _findById(user.statusMessages, card.statusMessageId)?.text;
    final subtitleParts = [?nickname, ?statusMessage];

    // カードが大きくなったのにアイコン・文字が160px時代の固定サイズのままだと
    // 中身が寂しく見えるため、カード幅に応じて緩やかにスケールさせる。
    final avatarRadius = (width * 0.11).clamp(18.0, 44.0);
    final padding = (width * 0.075).clamp(12.0, 28.0);
    final nameFontSize = (width * 0.09).clamp(14.0, 24.0);
    final subtitleFontSize = (width * 0.055).clamp(11.0, 16.0);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
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
                          card.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: nameFontSize,
                            fontWeight: FontWeight.bold,
                            color: background != null ? Colors.white : null,
                          ),
                        ),
                        Text(
                          subtitleParts.isEmpty
                              ? strings.workshopUnsetSubtitle
                              : subtitleParts.join(' / '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: subtitleFontSize,
                            color: background != null
                                ? Colors.white70
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(right: -4, top: -4, child: _DeleteBadge(onTap: onDelete)),
        ],
      ),
    );
  }

  static T? _findById<T>(List<T> items, String? id) {
    if (id == null) return null;
    for (final item in items) {
      final dynamic d = item;
      if (d.id == id) return item;
    }
    return null;
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

/// 工房: プロフィールカードの新規作成・編集ダイアログ（＝「選択画面」）。
/// 蔵に登録済みの素材の中から、このカードで使うものをそれぞれ選ぶ。
class _ProfileCardEditorDialog extends ConsumerStatefulWidget {
  const _ProfileCardEditorDialog({required this.user, this.existing});

  final AppUser user;
  final ProfileCard? existing;

  @override
  ConsumerState<_ProfileCardEditorDialog> createState() =>
      _ProfileCardEditorDialogState();
}

class _ProfileCardEditorDialogState
    extends ConsumerState<_ProfileCardEditorDialog> {
  late final TextEditingController _nameController;
  String? _iconId;
  String? _backgroundImageId;
  String? _nicknameId;
  String? _statusMessageId;
  String? _nameError;

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

  // カード名は必須項目だが、以前は未入力のまま保存を押しても_save()が
  // 無言でreturnするだけで、ボタンが反応していないように見えていた。
  // 押した結果が必ず見えるよう、ここでエラー表示してから閉じないようにする。
  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(
        () => _nameError = ref.read(appStringsProvider).fieldRequiredError,
      );
      return;
    }
    final card = ProfileCard(
      id: widget.existing?.id ??
          _newLocalId(),
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
    final strings = ref.watch(appStringsProvider);
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? strings.workshopCardDialogTitleNew
            : strings.workshopCardDialogTitleEdit,
      ),
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
                maxLength: kMaxWorkshopCardNameLength,
                decoration: InputDecoration(
                  labelText: strings.workshopCardNameLabel,
                  errorText: _nameError,
                ),
              ),
              _ImageChipPicker(
                label: strings.workshopFieldIcon,
                noneLabel: strings.workshopChoiceNone,
                selectedLabel: strings.workshopChoiceSelected,
                selectLabel: strings.workshopChoiceSelect,
                materials: widget.user.icons,
                selectedId: _iconId,
                onChanged: (id) => setState(() => _iconId = id),
              ),
              const SizedBox(height: 12),
              _ImageChipPicker(
                label: strings.workshopFieldBackground,
                noneLabel: strings.workshopChoiceNone,
                selectedLabel: strings.workshopChoiceSelected,
                selectLabel: strings.workshopChoiceSelect,
                materials: widget.user.backgroundImages,
                selectedId: _backgroundImageId,
                onChanged: (id) => setState(() => _backgroundImageId = id),
              ),
              const SizedBox(height: 12),
              _TextChipPicker(
                label: strings.workshopFieldNickname,
                noneLabel: strings.workshopChoiceNone,
                items: [for (final n in widget.user.nicknames) (n.id, n.text)],
                selectedId: _nicknameId,
                onChanged: (id) => setState(() => _nicknameId = id),
              ),
              const SizedBox(height: 12),
              _TextChipPicker(
                label: strings.workshopFieldStatusMessage,
                noneLabel: strings.workshopChoiceNone,
                items: [
                  for (final m in widget.user.statusMessages) (m.id, m.text),
                ],
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
          child: Text(strings.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(strings.save)),
      ],
    );
  }
}

class _ImageChipPicker extends StatelessWidget {
  const _ImageChipPicker({
    required this.label,
    required this.noneLabel,
    required this.selectedLabel,
    required this.selectLabel,
    required this.materials,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final String noneLabel;
  final String selectedLabel;
  final String selectLabel;
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
              label: Text(noneLabel),
              selected: selectedId == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final material in materials)
              ChoiceChip(
                avatar: CircleAvatar(backgroundImage: NetworkImage(material.url)),
                label: Text(material.id == selectedId ? selectedLabel : selectLabel),
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
    required this.noneLabel,
    required this.items,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final String noneLabel;
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
              label: Text(noneLabel),
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
